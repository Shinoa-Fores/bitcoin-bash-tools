#!/bin/bash
# Various bash bitcoin tools
#
# requires dc, the unix desktop calculator (which should be included in the
# 'bc' package)
#
# This script requires bash version 4 or above.
#
# This script uses GNU tools.  It is therefore not guaranted to work on a POSIX
# system.
#
# Copyright (C) 2013 Lucien Grondin (grondilu@yahoo.fr)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

if ((BASH_VERSINFO[0] < 4))
then
  echo "This script requires bash version 4 or above." >&2
  exit 1
else
  for script in {secp256k1,base58,bip-0173}.sh
  do 
    if ! . "$script"
    then
      1>&2 echo "This script requires the $script script file."
      exit 2
    fi
  done
fi

hash160() {
  openssl dgst -sha256 -binary |
  openssl dgst -rmd160 -binary
}

newBitcoinKey() {
    if [[ "$1" =~ ^[1-9][0-9]*$ ]]
    then $FUNCNAME "0x$(dc -e "16o$1p")"
    elif [[ "$1" =~ ^0x[[:xdigit:]]+$ ]]
    then
        local exponent="$1"
        local pubkey="$(point "$exponent")"
        jq . <<-ENDJSON
	{
	  "exponent": "$exponent",
	  "addresses": [
	    "$({
	      printf "\0"
	      echo "$pubkey" | xxd -p -r | hash160
	    } | encodeBase58Check)",
	    "$({
	      printf "\x05"
	      echo "21${pubkey}AC" | xxd -p -r | hash160
	    } | encodeBase58Check)",
	    "$(
	      echo "$pubkey" | xxd -p -r | hash160 |
	      segwit_encode bc 0
	    )"
	  ]
	}
	ENDJSON
    elif test -z "$1"
    then $FUNCNAME "0x$(openssl rand -hex 32)"
    else
        echo unknown key format "$1" >&2
        return 2
    fi
}

# toEthereumAddressWithChecksum() {
#     local addrLower=$(sed -r -e 's/[[:upper:]]/\l&/g' <<< "$1")
#     local addrHash=$(echo -n "$addrLower" | openssl dgst -sha3-256 -binary | xxd -p -c32)
#     local addrChecksum=""
#     local i c x
#     for i in {0..39}; do
#         c=${addrLower:i:1}
#         x=${addrHash:i:1}
#         [[ $c =~ [a-f] ]] && [[ $x =~ [89a-f] ]] && c=${c^^}
#         addrChecksum+=$c
#     done
#     echo -n $addrChecksum
# }

