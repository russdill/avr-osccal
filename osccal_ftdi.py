#!/usr/bin/python
#
# Copyright (C) 2016 Russ Dill <Russ.Dill@gmail.com>
#
# BSD-2-Clause
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
# IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import ftdi1
import math
import time
import sys

clock_rate = 32768
mosi = 1
miso = 2
rst = 3
buff = 6
ftdi_vendor = 0x0403
ftdi_product = 0x6010


def cmd(op, *args):
	return [op] + list(args)

def cmd2(op, arg, *args):
	return [op, arg & 0xff, arg >> 8] + list(args)

def delay(hz, t):
	b = []
	clocks = int(t * hz)
	if clocks > 8:
		b += cmd2(ftdi1.CLK_BYTES, (clocks / 8) - 1)
	if clocks % 8:
		b += cmd(ftdi1.CLK_BITS, (clocks % 8) - 1)
	return b

def write(ftdic, data):
	tc = ftdi1.write_data_submit(ftdic, str(bytearray(data)), len(data))
	if not tc:
		raise Exception('FTDI write error')
	ret = ftdi1.transfer_data_done(tc)
	if ret < 0:
		raise Exception(ftdi1.get_error_string(ftdic))

def read(ftdic, length):
	data = '\0' * length
	tc = ftdi1.read_data_submit(ftdic, data, length)
	if not tc:
		raise Exception('FTDI read error')
	ret = ftdi1.transfer_data_done(tc)
	if ret < 0:
		raise Exception(ftdi1.get_error_string(ftdic))
	return list(bytearray(data))


ftdic = ftdi1.new()
ftdi1.usb_open_desc_index(ftdic, ftdi_vendor, ftdi_product, None, None, 0)
ftdi1.usb_reset(ftdic)
ftdi1.set_interface(ftdic, ftdi1.INTERFACE_A)
ftdi1.set_bitmode(ftdic, 0, ftdi1.BITMODE_MPSSE)

b = []

# Calculate required clock rate, we bitbang out a clock on the data bit,
# so we need to run at the clock_rate * 2
hz = clock_rate * 2
numerator = 30000000.0;
if hz < 1000:
	b += cmd(ftdi1.EN_DIV_5)
	numerator /= 5.0
else:
	b += cmd(ftdi1.DIS_DIV_5)
divisor = int(round(numerator / hz - 1))
if divisor < 0:
	divisor = 0;
b += cmd2(ftdi1.TCK_DIVISOR, divisor)

# Reset target (hold low for 1ms)
b += cmd(ftdi1.SET_BITS_LOW, (1 << mosi),
		(1 << mosi) | (1 << buff) | (1 << rst))
b += delay(hz, 0.001)
b += cmd(ftdi1.SET_BITS_LOW, (1 << mosi) | (1 << rst),
		(1 << mosi) | (1 << buff) | (1 << rst))

# Wait 100ms for target to get started
b += delay(hz, 0.100)
write(ftdic, b)

# Wait for MISO to be high for 2000 clock periods
last_dot = 0.0
print 'Waiting for MISO high...',
while True:
	write(ftdic, cmd2(ftdi1.MPSSE_DO_READ, 4000 - 1))
	input = read(ftdic, 4000)
	if all(i == 0xff for i in input):
		break
	if last_dot > 0.500:
		sys.stdout.write('.')
		sys.stdout.flush()
		last_dot = 0
	else:
		last_dot += 4000.0 / hz
print

# Toggle data line for a while, 4000 * 4 toggles should be more than sufficient
# for the firmware to finish calibration. We simultaneously read the state of
# the MISO line.
print 'Sending training clock...'
out = [0x55] * 4000
b = cmd2(ftdi1.MPSSE_DO_WRITE | ftdi1.MPSSE_DO_READ, len(out) - 1, *out)
write(ftdic, b)

# Read back MISO data
input = read(ftdic, len(out))

# Look for bit toggle signal on MISO line. We need 8 transitions each lasting
# about 1 clock cycle, so 2 bits.
state = True
count = 0
transitions_seen = 0
err = False
success = False
for i in input:
	if (i == 0xff and state) or (i == 0x00 and not state):
		count += 8
		continue
	for b in range(7, -1, -1):
		bit = (i >> b) & 1
		if bit == state:
			count += 1
		else:
			if transitions_seen != 0:
				if count > 3:
					err = True
					break
			transitions_seen += 1
			count = 1
			state = bit == 1
	if err:
		break
	if transitions_seen == 8:
		success = True
		break

# Reset I/Os
b = cmd(ftdi1.SET_BITS_LOW, (1 << mosi) | (1 << rst),
		(1 << mosi) | (1 << buff) | (1 << rst))
write(ftdic, b)

if success:
	print "Success!"
else:
	print "Failed"
