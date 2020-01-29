#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause
#

#modified version for suhwan lab

name=`uname -n`

if [ -z ${RTE_SDK} ] ; then
	echo "*** RTE_SDK is not set, did you forget to do 'sudo -E ./setup.sh'"
	export RTE_SDK=/home/Susoon/workspace/dpdk-19.11
	export RTE_TARGET=x86_64-native-linuxapp-gcc
fi
sdk=${RTE_SDK}

if [ -z ${RTE_TARGET} ]; then
    echo "*** RTE_TARGET is not set, did you forget to do 'sudo -E ./setup.sh'"
    target=x86_64-native-linuxapp-gcc
else
    target=${RTE_TARGET}
fi

cmd=./app/${target}/pktgen

dpdk_opts="--master-lcore 7 -l 0-7 -n 8 --proc-type auto --log-level 8 --socket-mem 512 --file-prefix pg"

pktgen_opts="-T -P --crc-strip"
pktgen_opts="${pktgen_opts} -m [0-2:3-5].0"

load_file="-f themes/black-yellow.theme" #-f test/tx-rx-loopback.lua

echo ${cmd} ${dpdk_opts} ${black_list} -- ${pktgen_opts} ${load_file}
sudo ${cmd} ${dpdk_opts} ${black_list} -- ${pktgen_opts} ${load_file}

# Restore the screen and keyboard to a sane state
echo "[1;r"
echo "[99;1H"
stty sane
