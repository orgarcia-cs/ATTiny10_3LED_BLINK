;
; 3LED_Blink.asm
;
; Created: 12/23/2020 6:48:57 AM
; Author : Oscar R. Garcia
;
;
; build as currently implemented 12/22/2020 takes 764 bytes of 1024b EEPROM
;
; * You will need AVR Studio (or Microchip Studio now); as of this writing the current version is 7.0.2542
; * You will need TPI Programmer for ATTiny10, I chose to make one using [1] through an 32kb Arduino board
;
; if you do this on an UNO with 64k is no problem but I had to delete some code in the .ino file to make it fit
; on a 32k Duemiloviblahlblano board 
; or if you have $40 or something like that you can save yourself some fun and use their dedicated programmer [2]
;
; * You will need The Arduino IDE; version now is 1.8.13
; * You will need some way to access the tiny pins of the SOT23 ATTiny10, you can make or get PCBs that convert
; SOT23 to 8Pin DIP and then use whatever solder skills (wave soldering, doing it by hand etc.) to mount the board to the dip
; then you can stick in on a bread board and connect that to the UNO Board according to [1]
; Or you can get or build a SOT23 Socket board that lets you program the chip in situ.  The Socket adapters have come down since
; I first looked I think they are about $15 now, they were outrageously expensive at $50 a few years ago.
;
;
; [1] for building a programmer:  http://junkplusarduino.blogspot.com/p/attiny10-resources.html
; [2] for using a hardware ISP from ATMEL:  https://electronut.in/attiny10-hello/
;
; **************************************************************************************************************
;; The ATTiny10 is tiny, really tiny, it only comes in SMD versus DIP and is approximately 4x4mm in size
; It has 32 bytes of RAM and an address space of 1024bytes of EEPROM memory.
; It runs at 8/12Mhz and other speeds below that down to (uh I think) 120khz or so for really low power
; applications
; It is somewhat less powerful than the main chip of the Atari 2600 but to me they are comparable a bit.
; The strip down version of the 6501 - the 6507 runs at about 1.19Mhz and can access 8192 bytes of RAM
; They the frequently used 4kb for most games with some cartridges including another 4kb
; The 6507 has 13 Address Pins (8kb) and 8 bits for data (1 byte a fetch) and 7 support pins for
; timing/clock and other control signals
;
; The main drawback of the ATTiny10 of course is that it is a microcontroller and not a General Purpose
; CPU so this means it only has four output pins with one pin being shared with a reset pin
; versus the 8 pin data and 13pin address bus that the 6507 has.
;
; It is possible to add hardware that converts a single pin to a byte pin but with sufficient hardware
; implementation it might be able to make a small CPU that would have 8bits / 16bit spaces but would
; run at around 12Mhz / 10 or 10Mhz / 20 to account for the number of cycles required to issue control
; bits and data on a single wire in a similar fashion to I2C or other one/two wire communication protocols
; like that hardware bus that is used in cards uh... *click* *click* the CAN bus.  Probably a serious
; stretch to think that an ATTiny10 could run Linux but still sounds fun to try but...
;
; Anything more complicated than blinking an LED is gonna require a lot of single pin time multiplexing
; to do anything more complicated than blinking an LED so...
;
; On that note, how about blinking THREE LEDs!
;
; There is an inbuilt Pulse Wave Modulation in most ATTiny chips and I think this includes two
; I don't like it much though because you cannot vary the duty cycle, and the frequency steps available
; are a bit limited so here is a software version of that so that it can run all three pins.
; The idea is there is a larger pulse on/off cycle that are the blink speed and
; embedded within that are smaller brief on/off 1ms pulses that diminish the percieved intensity.
; Each pin is managed with a position/velocity counter with a position being the duration and
; velocity being how much that duration varies moment to moment
;
; These position/velocity terms are governed by a simple random number generator, it is possible to
; write a simple 8-bit random number generator but even simpler is just to activate and read the
; analog to digital converters and harvest a series of random bits to assemble a random number.
; This is not a very reliably random and entropic system; you would not want to use it to set RSA keys
; or anything like that but for blinking an LED it works pretty well.  Every time the ATTiny10 is reset
; a new set of values are loaded, it will keep trying until it gets something other than all zeros
; so it takes a few seconds to start.  Also it reset because I was vacumming dust off the workbench
; and it reset due to the high noise levels on the reset pin (where the ADC is that I read from) and
; began blinking in a pattern I have never seen before or since.  I also attach a small bit of wire
; to make it even noisier.
;
; If you don't mind messing with the 12V fuse switches you can disable the reset pin and enable a fourth
; pin to be used as an output.  That is not where the 12V comes in, you'll need 12V programmer to make the ATTiny10
;  programmable again.  The bought programmers do this (check and be sure they support 12V fuse setting).
;  So you could drive 4 LED pins if you modify this program appropriately
; I never do this because I'm not sure I can use my AVRISPII programmer will
; support driving the necessary outputs to reset the fuses the way a dedicated programmer could.
; The programmer is just an Arduino board and a custom PCB that I etched to program an ATTiny on an 8pin DIP.
; Also, getting noise from a pin with an LED stuck to it may not be possible and you'll have to add a software
; random key generator and find a way to access the clock so it doesn't always use the same key every time
; The 8bit pseudo=random below does not access the clock there are about 200bytes still available so it would be possible
; to access the clock but since it is not persistent the results may not be random at all...
; I have a similar one for the ATTiny85 chip which is conviniently availble as an 8pin DIP. and dwarfs the ATTiny10
; with its enormous 8kb of programmable memory and huge 512b of RAM and can be made to run at 20Mhz

.DEVICE ATtiny10

; assembler constant variables for use later in 8 bit Random Number Generator / X(n-1) = (A*X(0)+C)%M
.EQU DelayMult = 0x0f	; 0x000fffff loops is about 1 second at 8Mhz
.EQU X0		= 0x11		; Initializer "X(n=0)" - this is static, replace with noisy seed from A->D pin or something later...
.EQU A_Mult	= 0x41		; Multiplier  "A"
.EQU C_Inc		= 0x81		; Incrementor "C"
.EQU MODULO	= 0x100		; Won't use this defined constant just noting the modulo here for clarity "M"

.DSEG
.ORG $0040				; RAM starts at hex $40 store variables starting here
VADCRead3:		.Byte 1		; RAM Byte to store analog data read in
VRand8Read3:	.Byte 1		; RAM Byte to store analog data read in
VDelay65ms:		.Byte 1		; RAM Byte to store number of 0xffff loops to cycle through each about ~65ms long
VXred:			.Byte 1		; Current threshold position of Red
VXgreen:		.Byte 1		; Current threshold position of Green
VXblue:			.Byte 1		; Current threshold position of Blue
Vdxred:			.Byte 1		; Current threshold velocity of Red
Vdxgreen:		.Byte 1		; Current threshold velocity of Green
Vdxblue:		.Byte 1		; Current threshold velocity of Blue
VCycleRed:		.Byte 1		; Cycle counter for Red
VCycleGreen:	.Byte 1		; Cycle counter for Green
VCycleBlue:		.Byte 1		; Cycle counter for Blue
VXPos:			.Byte 1		; Use 2bytes of RAM to avoid repeating routines for RGB
VdxPos:			.Byte 1		; To avoid having three separate routines for RGB
A:			.BYTE 1		; 8 bit operand A for 8bit multiply
B:			.BYTE 1		; 8 bit operand B for 8bit multiply
Result16:	.BYTE 2		; 16 bit Result RAM Storage in format RH:RL
X_N:		.BYTE 1		; 8 bit storage for Random result

.CSEG ; code section
.ORG $0000 ; the starting address
main:
	; set up the stack
	ldi r16, high(RAMEND)
	out SPH, r16
	ldi r16, low(RAMEND)
	out SPL, r16
	
	; set clock divider
	ldi r16, 0x00 ; clock divided by 1
	ldi r17, 0xD8 ; the key for CCP
	out CCP, r17 ; Configuration Change Protection, allows protected changes
	out CLKPSR, r16 ; sets the clock divider

	; initialize port
	ldi r16, 0x00									; PUEB Setting 
	out PUEB, r16									; Disable All Pullups
	ldi r16, ((1<<DDB0) | (1<<DDB1) | (1<<DDB2))	; Set to Output PB0, PB1, PB2; PB3 remains as an input
	out DDRB, r16									; Set data direction
	ldi r16, 0x00									; sets all outputs Low
	out PORTB, r16									; Set the output register
	nop												; NOP, port operations seem to require one

	rcall InitializeValues							; Get random values from ADC for Variables

	ldi r16, 0x20									; Set a 1ms(or 250ms) delay
	sts VDelay65ms, r16								; Prepare Delay

	ldi r16, 0										; r16 will be used as a simple loop counter set to zero

;random specific initializations here before calling rand8
	ldi r16, X0			;initial seed into r16 - need to write a function to get an 8-bit random noise value from analog pin
	sts X_N, r16			;go ahead and store X0 into X_N to make looping below easier
;Execute -> X(n-1) = (A*X(0)+C)%M
	rcall rand8

loop:

	rcall VeryShortDelay							; pause for 1ms

	subi r16, 1
	brne loop										; Loop 256 times until subtracting one equals zero
	rcall UpdateThresholds							; adjust thresholds by dx

	rjmp loop


;------------------------- BEGIN SUBROUTINES --------------------------------------------
;-------------------------------------------------------------
VeryShortDelay:
	push r16					; Preserve r16
	
	ldi r16, VDelay65ms			; Retrieve Delay Value each +1 is about 250us

; start delay loop
VeryShortDelayLoop:
	rcall SetLEDs									; Turn on or off according to threshold; x and cycle values
	rcall UpdateCycle								; decrement all cycle counters
	subi r16, 1					; subtract 1
	brne VeryShortDelayLoop			; If MSByte is still not zero keep looping
; end delay loop
	pop r16						; Restore r16
	ret							; RETURN()

;-------------------------------------------------------------
ShortDelay:
	push r16					; Preserve r16
	push r17					; Preserve r17
	
	ldi r16, 0xff				; Set LSByte
	ldi r17, VDelay65ms			; Retrieve Delay Value each +1 is about 250us

; start delay loop
ShortDelayLoop:
	rcall SetLEDs									; Turn on or off according to threshold; x and cycle values
	rcall UpdateCycle								; decrement all cycle counters
	subi r16, 1					; subtract 1
	sbci r17, 0					; if r16 was 0, subtract 1
	brne ShortDelayLoop			; If MSByte is still not zero keep looping
; end delay loop
	pop r17						; Restore r17
	pop r16						; Restore r16
	ret							; RETURN()

;-------------------------------------------------------------
delay:
	; not really needed, but keep r16-r18
	push r16					; Preserve r16
	push r17					; Preserve r17
	push r18					; Preserve r18
	
	ldi r16, 0xff				; Store constant delay value
	ldi r17, 0xff				; Store constant delay value
	lds r18, VDelay65ms			; This value is the outer loop counter for number of 0xffff loops about 65ms each

; start delay loop
delayLoop:
	subi r16, 1					; subtract 1
	sbci r17, 0					; if r16 was 0, subtract 1
	sbci r18, 0					; if r17 was 0, subtract 1
	brne delayLoop				; while r18 is not 0, loop
; end delay loop

	pop r18						; Restore r18
	pop r17						; Restore r17
	pop r16						; Restore r16
	ret							; RETURN()

;-------------------------------------------------------------
readadc:
		push r16
		push r17
		ldi r16, 0				; Power reduction ADC turn off
		out PRR, r16			; Write out to turn ADC on
		ldi r16, ADC3			; MUX channel ADC3 at PB3 (ADC3 = 0b00000011
		out ADMUX, r16			; Set the channel - see page 91 of Datasheet 13.12.1
		ldi r16, 0x00			; Set ADCSRB ACD Register B to Free Running - see page 93 Section 13.12.3
		out ADCSRB, r16			; Write the Register B
		ldi r16, 0b11000110		; See 13.12.2  ADCSRA; Enable ADC, Start a Converstion, Do not auto trigger, Do not trigger interrupt, Do not request interrupt, and set System Clock -> ADC Clock scale factor div64 (8Mhz / 64 = 150khz)
		out ADCSRA, r16			; Set the ADC register A
;		ldi r16, (1 < ADC3D)	; Disable Digital Input on Pin 6 (ADC3/RESET) for analog read
;		out DIDR0, r16			; Write the register
adc_wait:
		in r16, ADCSRB			; Read from Control Register
		andi r16, 0b01000000	; Isolate bit-6 (ADSC) for testing if converstion is done (0) or still running (1)
		brne adc_wait			; If not zero (done) then keep looping until it is done

		in	r16, ADCL			; Read the result
		sts VADCRead3, r16		; Store result in memory variable
;		ldi r16, 0x00			; Re-Enable Digital Input on Pin 6 (ADC3/RESET) after analog read
;		out DIDR0, r16			; Write the register
		ldi r16, PRADC			; Power reduction ADC turn off
		out PRR, r16			; Write out to turn ADC off

		pop r17					; Restore r17
		pop r16					; Restore r16
		ret						; RETURN()

;-------------------------------------------------------------
noisy8bit:
		push r16				;Preserve used register
		push r17				;Preserve used register
		push r18				;preserve used register

		ldi r16, 8				; initialize 8x loop counter
		ldi r17, 0				; zero bit8read3 value
noisy8loop:
		rcall readadc			; get a value from unconnected ADC3 antennae
		lds r18, VADCRead3		; put value in register for processing
		andi r18, 0b00000001	; mask all but LSB
		lsl r17					; shift current value of register
		or r17, r18				; put the read LSB into LSB of bit8read
; SHORT DELAY BEFORE NEXT READ
		push r16
		lds r16, VDelay65ms
		push r16
		ldi r16, 0b00000001								; Delay value will be x 3 for short blink
		sts VDelay65ms, r16								; Set Delay to ~65ms x 3
		rcall delay										; Short Blink ON Delay
		pop r16
		sts VDelay65ms, r16 
		pop r16
; END SHORT DELAY
		subi r16, 1				; --i
		brne noisy8loop			; if counter is not zero loop until it is
		sts VRand8Read3, r17		; after all reads and shifts store a hopefully noisy byte of antennae data

		pop r18					; Pop register back
		pop r17					; Pop register back
		pop r16					; Pop register back
		ret						;RETURN()

;-------------------------------------------------------------
UpdateXPos:
		push r16
		push r17
		push r18
		push r19

		lds r16, VxPos				; get current x
		lds r17, VdxPos				; get current dx - Store result of dx and x'
		mov r18, r16				; make a copy of x
		add r18, r17				; get x' = x + dx - Store result of x' or dx
		mov r19, r18				; make a copy of x'
		andi r16, 0b10000000		; Mask out to only the sign bit
		andi r17, 0b10000000		; Mask out to only the sign bit
		andi r18, 0b10000000		; Mask out to only the sign bit
		or r18, r17					; will be false if and only if vx[7] x'[7] are 0
		and r17, r19				; will be true if and only if vx[7] x'[7] are 1

		cpi r16, 0x00				; is x[7] sign bit negative (1) or positive (0)
		brne URXxnegative			; branch if x[7] is 1 (-)
URXxpositive:
		cpi r17, 0x00				; test of x[7] was zero, test vx[7] AND x'[7] is one
		breq URXNoChange				; x[7] is zero; test vx[7] and x'[7] is one
		rjmp URXInvert				; Case 011 [x.vx.x']
URXxnegative:
		cpi r18, 0x00				; x[7] is one, test vx[7] OR x'[7] is zero
		brne URXNoChange				; branch if vx[7] AND x'[7] is both not zero
URXInvert:
		lds r17, VdxPos				; get current Vdx
		ldi r18, 0x00				; prepare for inversion
		sub r18, r17				; get 0 - dx
		sts VdxPos, r18				; Store inverted value
URXNoChange:
		lds r16, VxPos				; Get current x
		lds r17, VdxPos				; Get current dx
		add r16, r17				; add x + dx
		sts VxPos, r16				; save sum back to x
		pop r19
		pop r18
		pop r17
		pop r16
		ret

;-------------------------------------------------------------
UpdateGX:
		push r16
		push r17
		push r18
		push r19

		lds r16, VxGreen			; get current x
		lds r17, VdxGreen			; get current dx - Store result of dx and x'
		mov r18, r16				; make a copy of x
		add r18, r17				; get x' = x + dx - Store result of x' or dx
		mov r19, r18				; make a copy of x'
		andi r16, 0b10000000		; Mask out to only the sign bit
		andi r17, 0b10000000		; Mask out to only the sign bit
		andi r18, 0b10000000		; Mask out to only the sign bit
		or r18, r17					; will be false if and only if vx[7] x'[7] are 0
		and r17, r19				; will be true if and only if vx[7] x'[7] are 1

		cpi r16, 0x00				; is x[7] sign bit negative (1) or positive (0)
		brne UGXxnegative			; branch if x[7] is 1 (-)
UGXxpositive:
		cpi r17, 0x00				; test of x[7] was zero, test vx[7] AND x'[7] is one
		breq UGXNoChange				; x[7] is zero; test vx[7] and x'[7] is one
		rjmp UGXInvert				; Case 011 [x.vx.x']
UGXxnegative:
		cpi r18, 0x00				; x[7] is one, test vx[7] OR x'[7] is zero
		brne UGXNoChange				; branch if vx[7] AND x'[7] is both not zero
UGXInvert:
		lds r17, VdxGreen			; get current Vdx
		ldi r18, 0x00				; prepare for inversion
		sub r18, r17				; get 0 - dx
		sts VdxGreen, r18			; Store inverted value
UGXNoChange:
		lds r16, VxGreen			; Get current x
		lds r17, VdxGreen			; Get current dx
		add r16, r17				; add x + dx
		sts VxGreen, r16				; save sum back to x
		pop r19
		pop r18
		pop r17
		pop r16
		ret


;-------------------------------------------------------------
UpdateBX:
		push r16
		push r17
		push r18
		push r19

		lds r16, VxBlue			; get current x
		lds r17, VdxBlue			; get current dx - Store result of dx and x'
		mov r18, r16				; make a copy of x
		add r18, r17				; get x' = x + dx - Store result of x' or dx
		mov r19, r18				; make a copy of x'
		andi r16, 0b10000000		; Mask out to only the sign bit
		andi r17, 0b10000000		; Mask out to only the sign bit
		andi r18, 0b10000000		; Mask out to only the sign bit
		or r18, r17					; will be false if and only if vx[7] x'[7] are 0
		and r17, r19				; will be true if and only if vx[7] x'[7] are 1

		cpi r16, 0x00				; is x[7] sign bit negative (1) or positive (0)
		brne UBXxnegative			; branch if x[7] is 1 (-)
UBXxpositive:
		cpi r17, 0x00				; test of x[7] was zero, test vx[7] AND x'[7] is one
		breq UBXNoChange				; x[7] is zero; test vx[7] and x'[7] is one
		rjmp UBXInvert				; Case 011 [x.vx.x']
UBXxnegative:
		cpi r18, 0x00				; x[7] is one, test vx[7] OR x'[7] is zero
		brne UBXNoChange				; branch if vx[7] AND x'[7] is both not zero
UBXInvert:
		lds r17, VdxBlue			; get current Vdx
		ldi r18, 0x00				; prepare for inversion
		sub r18, r17				; get 0 - dx
		sts VdxBlue, r18			; Store inverted value
UBXNoChange:
		lds r16, VxBlue				; Get current x
		lds r17, VdxBlue			; Get current dx
		add r16, r17				; add x + dx
		sts VxBlue, r16				; save sum back to x
		pop r19
		pop r18
		pop r17
		pop r16
		ret

;-------------------------------------------------------------
SetLEDs:
		push r16
		push r17
		push r18

		ldi r18, 0										; LED status for PORTB, start with clear

		lds r16, VCycleRed								; Get current value of loop cycle
		lds r17, VXRed									; Get current on/off threshold
		cp r17, r16										; Set flags for threshold - loop value
		brsh RLEDOff									; Branch if threshold is same or higher than loop (OFF)
		ori r18, (1<<PB0)
RLEDOff:
		lds r16, VCycleGreen							; Get current value of loop cycle
		lds r17, VXGreen								; Get current on/off threshold
		cp r17, r16										; Set condition flags for (threshold - loop) test
		brsh GLEDOff									; Branch if threshold is same or higher than loop (OFF)
		ori r18, (1<<PB1)								; Turn on Green
GLEDOff:
		lds r16, VCycleBlue								; Get current value of loop cycle
		lds r17, VXBlue									; Get current on/off threshold
		cp r17, r16										; Set condition flags for (threshold - loop) test
		brsh BLEDOff									; Branch if threshold is same or higher than loop (OFF)
		ori r18, (1<<PB2)								; Turn on Blue
BLEDOff:
		out PORTB, r18									; Write out the values for LED signals
		nop
;	rcall delay
		pop r18
		pop r17
		pop r16
		ret

;-------------------------------------------------------------
UpdateThresholds:
	push r16

	lds r16, VxRed
	sts VxPos, r16
	lds r16, VdxRed
	sts VdxPos, r16
	rcall UpdateXPos
	lds r16, VxPos
	sts VxRed, r16
	lds r16, VdxPos
	sts VdxRed, r16

	lds r16, VxGreen
	sts VxPos, r16
	lds r16, VdxGreen
	sts VdxPos, r16
	rcall UpdateXPos
	lds r16, VxPos
	sts VxGreen, r16
	lds r16, VdxPos
	sts VdxGreen, r16

	lds r16, VxBlue
	sts VxPos, r16
	lds r16, VdxBlue
	sts VdxPos, r16
	rcall UpdateXPos
	lds r16, VxPos
	sts VxBlue, r16
	lds r16, VdxPos
	sts VdxBlue, r16

	pop r16
	ret

;-------------------------------------------------------------
UpdateCycle:
	push r16

	lds r16, VCycleRed
	subi r16, 1
	sts VCycleRed, r16
	lds r16, VCycleGreen
	subi r16, 1
	sts VCycleGreen, r16
	lds r16, VCycleBlue
	subi r16, 1
	sts VCycleBlue, r16

	pop r16
	ret

;-------------------------------------------------------------
InitializeValues:
	push r16

	rcall noisy8bit									; Get a random stream 8 bits long
	lds r16, VRand8Read3							; Store in register
	sts VXred, r16									; Random starting point of X
	rcall noisy8bit									; Get a random stream 8 bits long
	lds r16, VRand8Read3							; Store in register
	sts VXgreen, r16								; Random starting point of X
	rcall noisy8bit									; Get a random stream 8 bits long
	lds r16, VRand8Read3							; Store in register
	sts VXblue, r16									; Random starting point of X

RetryRed:
	rcall noisy8bit									; Get a random stream 8 bits long
	lds r16, VRand8Read3							; Store in register
	andi r16, 0x0f									; mask out top four bits
	subi r16, 0x08									; value will be 0-15 subtact 8 to get -7 to +7
	cpi r16, 0										; Test if new value is zero
	breq RetryRed									; Try another read until value is not zero
	sts Vdxred, r16									; Random starting point of vx
RetryGreen:
	rcall noisy8bit									; Get a random stream 8 bits long
	lds r16, VRand8Read3							; Store in register
	andi r16, 0x0f									; mask out top four bits
	subi r16, 0x08									; value will be 0-15 subtact 8 to get -7 to +7
	cpi r16, 0										; Test if new value is zero
	breq RetryGreen									; Try another read until value is not zero
	sts Vdxgreen, r16								; Random starting point of vx
RetryBlue:
	rcall noisy8bit									; Get a random stream 8 bits long
	lds r16, VRand8Read3							; Store in register
	andi r16, 0x0f									; mask out top four bits
	subi r16, 0x08									; value will be 0-15 subtact 8 to get -7 to +7
	cpi r16, 0										; Test if new value is zero
	breq RetryBlue									; Try another read until value is not zero
	sts Vdxblue, r16								; Random starting point of vx

	rcall noisy8bit									; Get a random stream 8 bits long
	lds r16, VRand8Read3							; Store in register
	andi r16, 0x7f									; mask out top bit for value of 0-127
	subi r16, 0xbf									; value will be 0-127 subtact 191 to get 65 to +191
	sts VCycleRed, r16								; Store cycle
	rcall noisy8bit									; Get a random stream 8 bits long
	lds r16, VRand8Read3							; Store in register
	andi r16, 0x7f									; mask out top bit for value of 0-127
	subi r16, 0xbf									; value will be 0-127 subtact 191 to get 65 to +191
	sts VCycleGreen, r16								; Store cycle
	rcall noisy8bit									; Get a random stream 8 bits long
	lds r16, VRand8Read3							; Store in register
	andi r16, 0x7f									; mask out top bit for value of 0-127
	subi r16, 0xbf									; value will be 0-127 subtact 191 to get 65 to +191
	sts VCycleBlue, r16								; Store cycle
	
	pop r16
	ret

/*
 * _8bitRandom.asm
 *
 *  Created: 3/15/2015 12:10:40 AM
 *   Author: Oscar R. Garcia
 */ 

 /**** Implement in Assembly this function
 m_w = <choose-initializer 16bit>;     --- must not be zero, nor 0x464fffff 
 m_z = <choose-initializer 16bit>;     --- must not be zero, nor 0x9068ffff 
 uint get_random()
{
	m_z = 36969 * (m_z & 65535) + (m_z >> 16);
	m_w = 18000 * (m_w & 65535) + (m_w >> 16);
	return (m_z << 16) + m_w;     --- 32-bit result 
}

;Actually forget that one, it is a bit more involved for an ATTiny10,
;this one below is simpler and will do the job and maybe just possibly fit alongside the intended app
;X(n+1) = (2053*X(n) + 13849) mod 65536
;
;Reference:  http://en.wikipedia.org/wiki/Linear_congruential_generator
;see http://www.avrfreaks.net/forum/very-fastsmall-random-number-generator?page=all
;
;Nah, forget that one too, used an 8bit variant that meets the Knuth requirements (as the one above does) of:
;X(n+1) = (a*X(n) + c) mod m
; So making some numbers up and trying in ExCel came up with the values below #3
;#1 - c & m are relatively prime (in other words both have only "1"as a common factor, confirmed using Euclidian Algorithm)
; see http://en.wikipedia.org/wiki/Euclidean_algorithm
;#2 - a-1 is divisible by all prime factors of m
;#3 - a-1 is a multiple of 4  if m is a multiple of 4
;Using a = 65, b = 129, m = 256 meets a criteria above for an 8bit random number generator with period 2^8-1
;will require 8*8 bit multiplication and it suffers from the limitations described in the article but it does appear to be uniform
;and should fit into ATtiny10 pretty easily, but... alongside other functions in 1K mem?
********/
rand8:
		push r16
		push r17
		push r18
		push r19

		lds r16, X_N
		sts A, r16				;store RAM location A for mult8 with X0 initial constant
		
		ldi r16, A_Mult			;A_Mult constant into r16
		sts B, r16				;store RAM location B for mult8 with A_Mult Constant

		rcall mult8				; A*B (or in other words Result16 = X0*A_Mult)
		lds r17, Result16+1		; store low byte of Result16 into r17
		lds r18, Result16		; store high byte of Result16 into r18
		ldi r19, 0x00			; dummy zero byte since adc does not have an immediate operand
		ldi r16, C_Inc			; store incrementor constant to r16
		add r17, r16			; add Low byte of Result16 + C_Inc
		adc r18, r19			; don't have adc immediate operand so have to supply a dummy zero register to do final addc
		sts X_N, r17			; update random seed with next value (the low byte, MOD 0x100 discards high byte)

		pop r19
		pop r18
		pop r17
		pop r16
		ret

mult8:	; Subroutine to multiply two 8 bit numbers
		; INPUT Arguments, Operand A located at RAM location described by "A",  Operand B located at RAM location described by "B"
		; OUTPUT Arguments, Result RH:RL located at RAM location described by "Result16"
		push r16
		push r17
		push r18
		push r19
		push r20
		push r21
		push r22
;Application Specific Initialization Here
		ldi r16, 8				;counter for while r16 > 0 branch loop
		lds r17, B				;shift test register for B[7:0]<- to test bit [7] to see if bit[7] should move to High Byte
		lds r18, A				;shift test register for A[7:0]-> to test bit [0] to see if an incremental sum should be added or skipped
		lds r19, B				;shifted sum operand register for B-> to cycle the adding of low byte
		ldi r20, 0				;shifted sum operand register for B<- to cycle the adding of high byte
		ldi r21, 0				;accumulator for result low = sigma r19
		ldi r22, 0				;accumulator for result high= sigma r20 + carry from sigma r19
mloop:		;Main Subroutine Loop
		sbrs r18,0				;test bit - skip next instruction if bit[0] is set (=1) - accumulate sums, in other words
		rjmp skip				;skip if bit[0] = zero
		add r21, r19			;accumulate result low byte
		adc r22, r20			;accumulate result high byte
skip:
		lsr r18					;ALWAYS DONE - shift r18 (operand A) -> for next bit test in main section
		lsl r19					;ALWAYS DONE - shift r19 (sigma result Low) for next addition
		lsl r20					;ALWAYS DONE - shift r20 (sigma result High) for next addition

		sbrs r17, 7
		rjmp skip2				;bit[7] = 0 so don't do next tests
		ori r20, 0x01			;set lowest bit to 1 otherwise jmp to skip2 and leave as 0
skip2:
		lsl r17					;already tested - shift r17 (low byte B) for next test during loop
		subi r16, 0x01			;subtract 1 from loop counter
		brne mloop				;if not yet zero loop again

		sts Result16, r22
		sts Result16+1, r21

		pop r22
		pop r21
		pop r20
		pop r19
		pop r18
		pop r17
		pop r16

		ret
