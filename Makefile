DEVICE = attiny45
PROGRAMMER = -c flyswatter2
F_CPU = 16000000UL

# Tuning input frequency
INPUT_FREQ = 32768UL

# Number of input frequency cycles to count
FREQ_CYCLES = 40

# Maximum delta in each OSCCAL update */
OSCCAL_MAXD = 32

# Oscillator version
OSC_VER = 5

# MOSI pin index
MOSI = 0

# MISO pin index
MISO = 1

FUSE_L = 0xe1
FUSE_H = 0xd5
FUSE_E = 0xfe
FUSEOPT = -U lfuse:w:$(FUSE_L):m -U hfuse:w:$(FUSE_H):m -U efuse:w:$(FUSE_E):m

CFLAGS = -Wall -g -Os -mmcu=$(DEVICE) --std=gnu99
CFLAGS += -DFREQ_CYCLES=$(FREQ_CYCLES)
CFLAGS += -DF_CPU=$(F_CPU) -DINPUT_FREQ=$(INPUT_FREQ)
CFLAGS += -DMOSI=$(MOSI) -DMISO=$(MISO)
CFLAGS += -DOSCCAL_MAXD=$(OSCCAL_MAXD) -DOSC_VER=$(OSC_VER)

CFLAGS += -ffunction-sections -fdata-sections -fpack-struct
CFLAGS += -fno-inline-small-functions  -fno-move-loop-invariants
CFLAGS += -fno-tree-scev-cprop -fno-move-loop-invariants -fno-tree-scev-cprop
CFLAGS += -Wl,--relax

CC = avr-gcc
OBJCOPY = avr-objcopy
OBJDUMP = avr-objdump
AVRDUDE = avrdude $(PROGRAMMER) -p $(DEVICE)

OBJS = osccal.o osccal_asm.o

all: osccal.hex

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.S
	$(CC) $(CFLAGS) -x assembler-with-cpp -c $< -o $@

fuse:
	$(AVRDUDE) $(FUSEOPT) -B 20

flash: osccal.hex
	$(AVRDUDE) -U flash:w:$<:i -B 20

osccal.elf: $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^
	avr-size $@

%.hex: %.elf
	$(OBJCOPY) -j .text -j .data -O ihex $< $@
	avr-size $@

current:
	@echo -n "Current OSCCAL: "
	@$(AVRDUDE) -U eeprom:r:/dev/stdout:h -qq | cut -f 1 -d ','
	@echo -n "Factory calibration: "
	@$(AVRDUDE) -U calibration:r:/dev/stdout:h -qq

disasm: osccal.elf
	$(OBJDUMP) -d $<

clean:
	-rm -f *.{hex,elf,o}

#---------------------------------------------------------------------
# ATtiny45
#---------------------------------------------------------------------
# Fuse extended byte:
# 0xfe = - - - -   - 1 1 0
#                        ^
#                        |
#                        +---- SELFPRGEN (enable self programming flash)
#
# Fuse high byte:
# 0xd5 = 1 1 0 1   0 1 0 1
#        ^ ^ ^ ^   ^ \-+-/
#        | | | |   |   +------ BODLEVEL 2..0 (brownout trigger level -> 2.7V)
#        | | | |   +---------- EESAVE (preserve EEPROM on Chip Erase -> not preserved)
#        | | | +-------------- WDTON (watchdog timer always on -> disable)
#        | | +---------------- SPIEN (enable serial programming -> enabled)
#        | +------------------ DWEN (debug wire enable)
#        +-------------------- RSTDISBL (disable external reset -> enabled)
#
# Fuse low byte:
# 0xe1 = 1 1 1 0   0 0 0 1
#        ^ ^ \+/   \--+--/
#        | |  |       +------- CKSEL 3..0 (clock selection -> HF PLL)
#        | |  +--------------- SUT 1..0 (BOD enabled, fast rising power)
#        | +------------------ CKOUT (clock output on CKOUT pin -> disabled)
#        +-------------------- CKDIV8 (divide clock by 8 -> don't divide)

###############################################################################

