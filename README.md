Summary:  Using ATTiny10 read ADC for random noise and use it to set the pulse blinking speed of 3 LEDs (i.e. RGB)


Manifest:


main.asm - The ATTiny10 assembly language code; compile using Microchip Studio;
don't forget to set the output device as ATTiny10, it will create the .hex file.

3LED_Blink.hex - ASCII hexadecimal coded output (e.g. "00FA" not the binary code),
copy using any simple text editor and paste this as one line into the Arudino Serial
Monitor after issuing the "R" Command to upload before 20sec timer expires.

SOT23_2_DIP.jpg - An ATTiny10 soldered by hand onto a pre-made SOT23 to 8-Pin DIP.

SOT23_Socket.jpg - Future task, make this into a board to load on Arduino for free
chip programming.

README.md - This file
LICENSE - Rights and limitations declaration.


Using the ATTiny10 for projects.

; * You will need AVR Studio (or Microchip Studio now); as of this writing the current version is 7.0.2542
; * You will need TPI Programmer for ATTiny10, I chose to make one using [1] through an Arduino board
;
; if you do this on an UNO usually is no problem but I had to delete some code in the .ino file to make it fit
; on a Duemiloviblahlblano board; I think I removed some of the fuse commands - didn't have to take much out.
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
; It is somewhat less powerful than the main chip of the Atari 2600 but to me they are a bit comparable.
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
; run at around 12Mhz/10 or 10Mhz/20 to account for the number of cycles required to issue control
; bits and data on a single wire in a similar fashion to I2C or other one/two wire communication protocols
; like that hardware bus that is used in cards uh... *click* *click* the CAN bus.  Probably a serious
; stretch to think that an ATTiny10 could run Linux but still sounds fun to try maybe an ancient OS like
; the C64 though with the limitations above and a bunch of hardware support it probably would run around
; 0.5Mhz at best.
;
; Anything other than blinking an LED is gonna require a lot of single pin time multiplexing
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
; pin to be used as an output.  That is not where the 12V comes in though, however
; you'll need 12V programmer to make the ATTiny10
; programmable again.  The bought programmers do this (check and be sure they support 12V fuse setting).
; So you could drive 4 LED pins if you modify this program appropriately
; I never do this because I'm not sure I can use my AVRISPII programmer will
; support driving the necessary outputs to reset the fuses the way a dedicated programmer could.
; The programmer is just an Arduino board and a custom PCB that I etched to program an ATTiny on an 8pin DIP.
; Also, getting noise from a pin with an LED stuck to it may not be possible and you'll have to add a software
; random key generator and find a way to access the clock so it doesn't always use the same key every time
; The 8bit pseudo=random below does not access the clock there are about 200bytes still available so it would be possible
; to access the clock but since it is not persistent the results may not be random at all...
; I have a similar one for the ATTiny85 chip which is conviniently availble as an 8pin DIP. and dwarfs the ATTiny10
; with its enormous 8kb of programmable memory and huge 512b of RAM and can be made to run at 20Mhz
;
;
; Future things to try:
;
; Interfacing with low pin devices like I2C based devices, though 32bytes of RAM is imposing for this.
