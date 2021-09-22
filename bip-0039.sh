#!/usr/bin/env bash

ceil() { echo $(( ($1 + $2 + 1)/$2 )); }

pbkdf2_step() {
  local c hash_name="$1" key="$2"
  for c in "${@:3}"
  do printf '%02x\n' "$c"
  done |
  while read -r
  do printf %b "\x$REPLY"
  done |
  openssl dgst -"$hash_name" -hmac "$key" -binary |
  xxd -p -c 1 |
  while read -r
  do echo $((0x$REPLY))
  done
}
function pbkdf2() {
  case "$PBKDF2_METHOD" in
    python)
      local command_str
      printf -v command_str 'import hashlib; print(hashlib.pbkdf2_hmac("%s","%s".encode("utf-8"), "%s".encode("utf-8"), %d).hex())' "$@"
      python -c "$command_str"
      ;;
    *)
      # Translated from https://github.com/bitpay/bitcore/blob/master/packages/bitcore-mnemonic/lib/pbkdf2.js
      # /**
      # * PBKDF2
      # * Credit to: https://github.com/stayradiated/pbkdf2-sha512
      # * Copyright (c) 2014, JP Richardson Copyright (c) 2010-2011 Intalio Pte, All Rights Reserved
      # */
      local hash_name="$1" key_str="$2" salt_str="$3"
      local -ai key salt u t block1
      local -i hLen
      hLen="$(openssl dgst "-$hash_name" -binary <<<"foo" |wc -c)"
      local -i iterations=$4 dkLen=${5:-hLen} i j k destPos hLen len
      
      local -i l=dkLen/hLen
      local -i r=$((dkLen-(l-1)*hLen))

      local c
      for ((i=0; i<${#key_str}; i++))
      do
	printf -v c "%d" "'${key_str:i:1}"
	key+=($c)
      done

      for ((i=0; i<${#salt_str}; i++))
      do
	printf -v c "%d" "'${salt_str:i:1}"
	salt+=($c)
      done

      for ((i=0; i<dKlen; i++)); do dk+=(0); done
      for ((i=0; i< hLen; i++)); do u+=(0); t+=(0); done

      for c in ${salt[@]}; do block1+=($c); done
      for i in {1..4}; do block1+=(0); done

      for ((i=1;i<=l;i++))
      do
	block1[${#salt[@]}+0]=$((i >> 24 & 0xff))
	block1[${#salt[@]}+1]=$((i >> 16 & 0xff))
	block1[${#salt[@]}+2]=$((i >>  8 & 0xff))
	block1[${#salt[@]}+3]=$((i >>  0 & 0xff))
	
	u=($(pbkdf2_step "$hash_name" "$key_str" "${block1[@]}"))
	printf "PBKFD2 iteration %10d/%d" 1 $iterations >&2
	t=(${u[@]})
	for ((j=1; j<iterations; j++))
	do
	  printf "\rPBKFD2 iteration %10d/%d" $((j+1)) $iterations >&2
	  u=($(pbkdf2_step "$hash_name" "$key_str" "${u[@]}"))
	  for ((k=0; k<hLen; k++))
	  do t[k]=$((t[k]^u[k]))
	  done
	done
	echo >&2
	
	destPos=$(( (i-1)*hLen ))
	if ((i == l))
	then len=r
	else len=hLen
	fi
	for ((k=0; k<len; k++))
	do dk[destPos+k]=${t[k]}
	done
	
      done
      printf "%02x" ${dk[@]}
      echo
    ;;
  esac
}

complete -W "$(< wordlist.txt)" mnemonic-to-seed
function mnemonic-to-seed() {
  local OPTIND 
  if getopts hb o
  then
    shift $((OPTIND - 1))
    case "$o" in
      h) cat <<-USAGE_3
	${FUNCNAME[0]} -h
	${FUNCNAME[0]} -b word word...
	USAGE_3
        ;;
      b) ${FUNCNAME[0]} "$@" |xxd -p -p ;;
    esac
  elif [[ $# =~ ^(12|15|18|21|24)$ ]]
  then 
    {
      echo 16o0
      for word
      do
        grep -n "^$word$" wordlist.txt |
        cut -d: -f1 |
        sed "{ s/^/2048*/; s/$/ 1-+ # $word/ }"
      done
      echo 2 $(($#*11/33))^ 0k/ f
    } |
    dc |
    {
      read
      create-mnemonic $(
        printf "%$(($#*11*32/33/4))s" $REPLY |
        sed 's/ /0/g'
      ) || 1>&2 echo "undocumented error"
    } |
    tail -n 1 |
    if read -a words
    [[ "${words[@]: -1}" != "${@: -1}" ]]
    then
      1>&2 echo "wrong checksum : $REPLY instead of ${@: -1}"
      return 5
    fi
    pbkdf2 sha512 "$*" "mnemonic$BIP39_PASSPHRASE" 2048
  else return 1
  fi
}

function create-mnemonic() {
  local OPTIND OPTARG o
  if getopts hPpf: o
  then
    shift $((OPTIND - 1))
    case "$o" in
      h) cat <<-USAGE
	${FUNCNAME[@]} -h
	${FUNCNAME[@]} entropy-size
	${FUNCNAME[@]} [-p|-P] words ...
	USAGE
        ;;
      p)
	read -p "Passphrase: "
	BIP39_PASSPHRASE="$REPLY" ${FUNCNAME[0]} "$@"
	;;
      P)
	local passphrase
	read -p "Passphrase:" -s passphrase
	read -p "Confirm passphrase:" -s
	if [[ "$REPLY" = "$passphrase" ]]
	then BIP39_PASSPHRASE=$passphrase $FUNCNAME "$@"
	else echo "passphrase input error" >&2; return 3;
	fi
	;;
    esac
  elif [ ! -L wordlist.txt ]
  then
    1>&2 echo Please create a symbolic link to a wordlist file.
    1>&2 echo Name it wordlist.txt and place it in the current directory.
    return 1
  elif 
    declare -a wordlist=($(< wordlist.txt))
    (( ${#wordlist[@]} != 2048 ))
  then
    1>&2 echo unexpected number of words in wordlist file
    return 2
  elif [[ $1 =~ ^(128|160|192|224|256)$ ]]
  then $FUNCNAME $(openssl rand -hex $(($1/8)))
  elif [[ "$1" =~ ^([[:xdigit:]]{2}){16,32}$ ]]
  then
    local hexnoise="${1^^}"
    local -i ENT=${#hexnoise}*4 #bits
    if ((ENT % 32))
    then
      1>&2 echo entropy must be a multiple of 32, yet it is $ENT
      return 2
    fi
    { 
      # "A checksum is generated by taking the first <pre>ENT / 32</pre> bits
      # of its SHA256 hash"
      local -i CS=$ENT/32
      local -i MS=$(( (ENT+CS)/11 )) #bits
      #1>&2 echo $ENT $CS $MS
      echo "$MS 1- sn16doi"
      echo "$hexnoise 2 $CS^*"
      echo -n "$hexnoise" |
      xxd -r -p |
      openssl dgst -sha256 -binary |
      head -c1 |
      xxd -p -u
      echo "0k 2 8 $CS -^/+"
      echo "[800 ~r ln1-dsn0<x]dsxx Aof"
    } |
    dc |
    while read -r
    do echo ${wordlist[REPLY]}
    done |
    {
      mapfile -t
      echo "${MAPFILE[*]}"
    }
  elif (($# == 0))
  then $FUNCNAME 160
  else
    1>&2 echo parameters have insufficient entropy or wrong format
    return 4
  fi
}
