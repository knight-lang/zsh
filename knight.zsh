#!/bin/zsh

################################################################################
#                                    Setup                                     #
################################################################################

## Set options
setopt extendedglob     # Required for advanced globbing features
setopt noglobalexport   # `typeset -g` doesn't imply the variable is exported
setopt warncreateglobal # Make sure global variables aren't created accidentally

## Seed `$RANDOM` for the knight `RANDOM` function.
# (If you don't seed it, ZSH will always use the same initial seed)
RANDOM=$(date +%s)

## Predeclare global variables so `warncreateglobal` won't get mad at us.
typeset -g REPLY  # "Return value" from functions
typeset -ga reply # Same as REPLY, but when an array is needed

## Print out a message and exit the program
die () {
	print -- "${ZSH_SCRIPT:t}: $*" >&2
	exit 1
}

################################################################################
#                                    Arrays                                    #
################################################################################

## Array are implemented via the variable `arrays`, an associative array itself.
# How it works is the "key" is `aNUMBER`, where `NUMBER` is a unique ID for each
# array (such as `a12`, or whatever).
# 
# The length of the array is stored as just `$key`, ie the length of array `a34`
# is simply `$arrays[a34]`.
#
# The elements of the array are stored as `$key:$idx` (`idx` starts at 0), ie
# the first element of `a34` would be `$arrays[a34:1]`.
typeset -gA arrays=(a0 0)

## Creates a new array from arguments, setting `REPLY` to its name
new_ary () {
	# Empty arrays are always `a0`; this is used in things like `to_bool`.
	(( # )) || { REPLY=a0; return }

	# Set `REPLY` to the name of the array
	REPLY=a$#arrays

	# Set the length of the array
	arrays[$REPLY]=$#

	# Set each element of the array
	local element i=0
	for element do
		arrays[$REPLY:$((i++))]=$element
	done
}

## Joins an array
# First argument should be the string to join with, the second should be the
# array name. Converts each element in the array to a string first, and sets
# `$REPLY` to the end result
ary_join () {
	# We have to have `result` be local because `to_str` will clobber `REPLY`.
	local result i

	for (( i = 0; i < arrays[$2]; i++ )) do
		to_str $arrays[$2:$i]
		result+=${result:+$1}$REPLY
	done

	REPLY=$result
}

################################################################################
#                                 Conversions                                  #
################################################################################

to_str () case ${1:0:1} in
	[sn])  REPLY=${1:1} ;;
	T)     REPLY=true ;;
	F)     REPLY=false ;;
	N)     REPLY= ;;
	a)     ary_join $'\n' $1 ;; # `ary_join` sets result
	*) die "unknown type for $0: $1" ;;
esac

to_int () case ${1:0:1} in
	s) typeset -g match mbegin mend # so `warncreateglobal` wont getmad
	case ${1##s[[:space:]]#} in # AFAICT, zsh doesn't have a C-style `atoi`.
		((#b)((-|)<->)*) REPLY=$match[1] ;;
		((#b)(+<->)*) REPLY=${match[1]#+} ;;
		(*) REPLY=0 ;;
		esac ;;
	[FN]) REPLY=0 ;;
	T)    REPLY=1 ;;
	n)    REPLY=${1#?};;
	a)    REPLY=$arrays[$1] ;;
	*) die "unknown type for $0: $1" ;;
esac

to_bool () [[ $1 != (s|[na]0|[FN]) ]]

to_ary () case $1 in # Notably not `${1:0:1}`
	[sFN]) reply=() ;;
	T)     reply=(T) ;;
	s*)    reply=(s${(s::)^1#s}) ;;
	n*)    reply=(n${${1#n}%%<->}${(s::)^1##n(-|)}) ;;
	a*) reply=()
		while (( $#reply < arrays[$1] )) do
			reply+=$arrays[$1:$#reply]
		done ;;
	*) die "unknown type for $0: $1" ;;
esac

################################################################################
#                                  Utilities                                   #
################################################################################

newbool () if ((?)) then REPLY=F; else REPLY=T; fi

dump () case ${1:0:1} in
	[TFn]) to_str $1; print -nr -- $REPLY ;;
	N) print -n null ;;
	s) local escaped=${1#s}
		escaped=${escaped//$'\\'/\\\\}
		escaped=${escaped//$'\n'/\\n}
		escaped=${escaped//$'\r'/\\r}
		escaped=${escaped//$'\t'/\\t}
		escaped=${escaped//$'\"'/\\\"}
		print -nr -- \"$escaped\" ;;
	a) print -n \[
		local i
		for (( i = 0; i < $arrays[$1]; i++ )) do
			(( i )) && print -n ', '
			dump $arrays[$1:$i]
		done
		print -n \] ;;
	*) die "unknown type for $0: $1"
esac

eql () {
	[[ $1 = $2 ]] && return 0
	[[ ${1:0:1} == a && ${2:0:1} == a ]] || return 1
	(( arrays[$1] == arrays[$2] )) || return 1

	local i
	for (( i = 0; i < $arrays[$1]; i++ )) do
		eql $arrays[$1:$i] $arrays[$2:$i] || return 1
	done
	return 0
}

functions -M min 1 -1
min () {
	local arg min=$(($1)); shift # do `$(($1))` so we have a math eval already
	for arg do (( arg < min ? (min=arg) : min )) done
}

functions -M cmp 2 2
cmp () { (( $1 < $2 ? -1 : $1 > $2 )); : }

compare () case ${1:0:1} in
	s) to_str $2;
		if [[ ${1#s} < $REPLY ]]; then REPLY=-1
		else; [[ ${1#s} == $REPLY ]]; REPLY=$?; fi ;;
	T) to_bool $2; REPLY=$?;;
	F) to_bool $2; REPLY=$(( -!? ));;
	n) to_int $2; REPLY=$(( cmp(${1#n},REPLY) )) ;;
	a) to_ary $2
		local -a rep=($reply)
		local i min=$(( min(arrays[$1], $#rep) ))
		for (( i = 0; i < min; i++ )) do
			compare $arrays[$1:$i] $rep[i+1]
			(( REPLY )) && return
		done
		REPLY=$(( cmp(arrays[$1], $#rep) )) ;;
	*) die "unknown type for $0: $1"
esac

################################################################################
#                                   Parsing                                    #
################################################################################

typeset -ga asts

# readonly -A arities=(${=${:-\
# 	{P,R}\ 0 \
# 	{\$,O,E,B,C,Q,!,L,D,\,,A,\[,\],\~}\ 1 \
# 	{\-,\+,\*,\/,\%,\^,\?,\<,\>,\&,\|,\;,\=,W}\ 2 \
# 	{G,I}\ 3
# 	S\ 4}})

typeset -A arities
for k in \
	{P,R}\ 0 \
	{\$,O,E,B,C,Q,!,L,D,\,,A,\[,\],\~}\ 1 \
	{\-,\+,\*,\/,\%,\^,\?,\<,\>,\&,\|,\;,\=,W}\ 2 \
	{G,I}\ 3 \
	S\ 4
do
	_tmp=(${=k})
	arities[$_tmp[1]]=$_tmp[2]
done
unset _tmp

typeset -g LINE 
function next_token {
	# Strip leading whitespace and comments
	LINE=${LINE##(\#[^$'\n']#|[:()\{\}[:space:]]#)#}

	# Return if the line is empty
	[[ -z $LINE ]] && return 1

	# Parse the token
	typeset -g match mbegin mend # Used for pattern matching
	case $LINE in
		(@*) REPLY=a0 LINE=${LINE:1}; return 0 ;;
		((#b)(<->)*)                     REPLY=n$match[1] ;;
		((#b)([_[:lower:][:digit:]]##)*) REPLY=v$match[1] ;;
		((#b)(\"[^\"]#\"|\'[^\']#\')*)   REPLY=s${${match#?}%?} ;;
		((#b)([TFN][_[:upper:]]#)*)      REPLY=${LINE:0:1} ;;
		((#b)([_[:upper:]]##|[\+\-\$\+\*\/\%\^\<\>\?\&\|\!\;\=\~\,\[\]])*)
			REPLY=f${LINE:0:1} ;;
		(*) die "unknown token start: ${(q)LINE:0:1}" ;;
	esac

	# Replace the line; the return value is also 0
	LINE=${LINE:$mend[1]}
}


## FS is 
readonly FS=$'\0'

function generate_ast {
	next_token || return # If there was a problem return early

	[[ ${REPLY:0:1} != f ]] && return # If we're not a function just return early

	local i token=$REPLY arity=$arities[${REPLY#f}]
	for (( i = 1; i <= arity; i++ )); do
		generate_ast || die "missing argument $i for function ${(qq)token:1:2}"
		token=$token$FS$REPLY
	done

	asts+=($token)
	REPLY=A$#asts
}

################################################################################
#                                  Execution                                   #
################################################################################
typeset -gA variables

function eval_kn {
	LINE=${1?}
	generate_ast || die 'no program given'
	run $REPLY
}

function run {
	# Handle variables and non-asts
	if [[ ${1:0:1} = v ]]; then
		REPLY=$variables[$1]
		[[ -n $REPLY ]] || die "unknown variable ${1#v}"
		return
	elif [[ ${1:0:1} != A ]]; then
		REPLY=$1
		return
	fi

	# TODO
	local i=$IFS
	IFS=$FS
	set -- ${=asts[${1#A}]#f}
	IFS=$i
	unset i
	local fn=$1
	shift

	# Functions which don't automatically execute all their args.
	case $fn in
		B)  REPLY=$1; return;;
		=)  run $2; variables[$1]=$REPLY; return;;
		\&) run $1; to_bool $REPLY && run $2; return;;
		\|) run $1; to_bool $REPLY || run $2; return;;
		W)  while run $1; to_bool $REPLY; do run $2; done; REPLY=N; return;;
		I)  run $1; to_bool $REPLY; run ${@[2+?]}; return;;
	esac

	local -a _tmp
	local _tmp2
	for _tmp2 do run $_tmp2; _tmp+=$REPLY done
	set -- $_tmp

	case $fn in
		# ARITY 0
		R) REPLY=n$RANDOM ;;
		P) read -r REPLY; REPLY=s${REPLY%%$'\r'#} ;;

		# ARITY 1
		C) run $1 ;;
		E) to_str $1; eval_kn $REPLY ;;
		\~) to_int $1; REPLY=n$((-REPLY)) ;;
		$) to_str $1; REPLY=s$($=REPLY) ;;
		!) ! to_bool $1; newbool ;;
		Q) to_int $1; exit $REPLY ;;
		L) case ${1:0:1} in
			s) REPLY=n${#1#s} ;;
			a) REPLY=n$arrays[$1] ;;
			*) to_ary $1; REPLY=n$#reply ;;
			esac ;;
		D) dump $1; REPLY=$1 ;;
		O) if to_str $1; [[ ${REPLY: -1} = \\ ]]
			then print -rn -- ${REPLY%?}
			else print -r  -- $REPLY
			fi
			REPLY=N ;;
		,) new_ary $1 ;;
		A) case ${1:0:1} in
			s) 1=${1#s}; REPLY=n$(( #1 )) ;;
			n) REPLY=s${(#)1#n} ;;
			*)  die "unknown argument to $fn: $1" ;;
			esac ;;
		\[) to_ary $1; REPLY=$reply[1] ;;
		\]) case ${1:0:1} in
			s) REPLY=s${1:2} ;;
			*) to_ary $1; shift reply; new_ary $reply ;;
			esac ;;

		# ARITY 2
		\;) REPLY=$2 ;;
		+) case ${1:0:1} in
			n) to_int $2; REPLY=n$((${1#?} + REPLY)) ;;
			s) to_str $2; REPLY=s${1#?}$REPLY ;;
			a) to_ary $1; local old=($reply)
			   to_ary $2; new_ary $old $reply ;;
			*) die "unknown argument to $fn: $1"
			esac ;;
		-) to_int $2; REPLY=n$((${1#?} - REPLY)) ;;
		\*) case ${1:0:1} in
			n) to_int $2; REPLY=n$((${1#?} * REPLY)) ;;
			s) to_int $2; set -- ${1#s}; REPLY=s${(pl:$((${#1} * REPLY))::$1:)} ;;
			a) to_ary $1; to_int $2
				local -a ary
				local i=
				for (( i = 0; i < $REPLY; i++ )); do
					ary+=($reply)
				done
				new_ary $ary ;;
			*) die "unknown argument to $fn: $1"
			esac ;;
		/) to_int $2; REPLY=n$((${1#?} / REPLY)) ;;
		%) to_int $2; REPLY=n$((${1#?} % REPLY)) ;;
		\^) case ${1:0:1} in
			n) to_int $2; REPLY=n$((${1#?} ** REPLY)) ;;
			a) to_str $2; ary_join "$REPLY" $1; REPLY=s$REPLY ;; # TODO: whyis reply quoted here??
			*) die "unknown argument to $fn: $1"
			esac ;;
		\?) eql $1 $2; newbool ;;
		\<) compare $1 $2; (( REPLY < 0 )); newbool ;;
		\>) compare $1 $2; (( REPLY > 0 )); newbool ;;
		G) case ${1:0:1} in
			s) to_int $2
				local start=$REPLY
				to_int $3
				REPLY=s${${1#s}:$start:$REPLY} ;;
			a) to_ary $1
				to_int $2; shift $REPLY reply
				to_int $3; shift -p $(($#reply - REPLY)) reply
				new_ary $reply ;;
			*) die "unknown argument to $fn: $1" ;;
			esac ;;
		S) case ${1:0:1} in
			s) to_int $2; local start=$REPLY
				to_int $3; local len=$REPLY
				to_str $4
				REPLY=${1:0:$((start+1))}$REPLY${1:$((start+1+len))} ;;
			a) to_ary $1; local answer=($reply)
				to_int $2; local start=$REPLY
				to_int $3; local len=$REPLY
				to_ary $4;
				answer[start+1,start+len]=($reply)
				new_ary $answer ;;
			*) die "unknown argument to $fn: $1" ;;
			esac ;;
		*) die "BUG: unknown function $fn" ;;
	esac
	return 0
}

if [[ $1 = -e ]]; then
	eval_kn $2
else
	eval_kn "$(<$2)"
fi
