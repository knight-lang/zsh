#!/bin/zsh

setopt extendedglob rcquotes #nounset
setopt NO_GLOBAL_EXPORT noshortloops warncreateglobal localloops

RANDOM=$(date +%s)

typeset -gA arrays=(a0 0)
typeset -ga reply
typeset -g REPLY LINE FS=$'\x1C'

die () { print ${ZSH_SCRIPT:t}: $@ >&2; exit 1 }
bug () die bug: $@

new_ary () {
	((#)) || { REPLY=a0; return }

	typeset -g ARY_IDX
	REPLY=a$((++ARY_IDX))
	arrays[$REPLY]=$#

	integer i
	for (( ; i < $#; i++ )) do
		arrays[$REPLY$FS$i]=${@[$((i+1))]}
	done
}

to_str () case ${1-REPLY} in
	[sn]*) REPLY=${1:1} ;;
	T)     REPLY=true ;;
	F)     REPLY=false ;;
	N)     REPLY= ;;
	a*)    to_ary $1; ajoin $'\n' $reply ;;
	*) bug unknown type for to_str: $1 ;;
esac

to_num () case ${1-REPLY} in
	# s[[:space:]]#([-+]|)<->) dbg yes ;;
	s*)   REPLY=$(ruby -e 'puts $*[0].to_i' -- ${1#s});; # TODO
	n*)   REPLY=${1#?};;
	[FN]) REPLY=0 ;;
	T)    REPLY=1 ;;
	a*)   REPLY=$arrays[$1] ;;
	*) bug unknown type for to_num: $1 ;;
esac

to_bool () [[ ${1-REPLY} != (s|[na]0|[FN]) ]]

to_ary () case ${1-REPLY} in
	[sFN]) reply=() ;;
	T)     reply=(T) ;;
	a*)    reply=(); while (($#reply < arrays[$1])) { reply+=$arrays[$1$FS$#reply] } ;;
	s*)    reply=(s${(s::)^1#s}) ;;
	n*)    reply=(n${${1#n}%%<->}${(s::)^1##n(-|)})  ;;
	*) bug unknown type for to_ary: $1 ;;
esac

ajoin () {
	local arg result sep=$1
	shift
	for arg do to_str $arg; result+=${result:+$sep}$REPLY done
	REPLY=$result
}

dump () case ${1-REPLY} in
	[TF]|n*) to_str $1; print -nr -- $REPLY ;;
	N) print -n null ;;
	s*) 1=${1#s}
		1=${1//$'\\'/\\\\}
		1=${1//$'\n'/\\n}
		1=${1//$'\r'/\\r}
		1=${1//$'\t'/\\t}
		1=${1//$'\"'/\\\"}
		print -nr -- \"$1\" ;;
	a*) 
		print -n \[
		local i
		for (( i = 0; i < $arrays[$1]; i++ )) {
			(( i )) && print -n ', '
			dump $arrays[$1$FS$i]
		}
		print -n \] ;;
	*) bug unknown type for dump: $1
esac

eql () {
	[[ $1 = $2 ]] && return
	[[ ${1:0:1} == a && ${2:0:1} == a ]] || return
	(( arrays[$1] == arrays[$2] )) || return

	local i
	for (( i = 0; i < $arrays[$1]; i++ )) {
		eql $arrays[$1$FS$i] $arrays[$2$FS$i] || return
	}
}

functions -M min 1 -1
min () {
	local arg min=$1; shift
	for arg { (( arg < min )) && min=$arg }
	(( min )); :
}

functions -M cmp 2 2
cmp () { (( $1 < $2 ? -1 : $1 > $2 )); : }

compare () case $1 in
# TODO
	s*) to_str $2;
		if [[ ${1#s} < $REPLY ]]; then REPLY=-1
		else; [[ ${1#s} > $REPLY ]]; REPLY=$?; fi ;;
	[TF]) to_num $1; local a=$REPLY; if to_bool $2; then REPLY=1; else REPLY=0; fi; compare n$a n$REPLY ;;

	n*) to_num $2; (( REPLY = cmp(${1#n}, REPLY) )) ;;
	a*)
		to_ary $2
		local -a rep=($reply)
		local i min=$(( min(arrays[$1], $#rep) ))
		for (( i = 0; i < min; i++ )) {
			compare $arrays[$1$FS$i] $rep[$((i+1))]
			(( REPLY )) && return
		}
		(( REPLY = cmp(arrays[$1], $#rep) )) ;;
	*) bug unknown type for compare: $1
esac

function next_token {
	# Strip leading whitespace and comments
	LINE=${LINE##(\#[^$'\n']#|[:()\{\}[:space:]]#)#}

	[[ -z $LINE ]] && return 1

	case $LINE in
		((#b)(<->)*)                     REPLY=n$match[1] ;;
		((#b)([_[:lower:][:digit:]]##)*) REPLY=i$match[1] ;;
		((#b)(\"[^\"]#\"|\'[^\']#\')*)   REPLY=s${${match#?}%?} ;;
		(@*) REPLY=a0 LINE=${LINE:1}; return 0 ;;
		((#b)([TFN][_[:upper:]]#)*)      REPLY=${LINE:0:1} ;;
		((#b)([_[:upper:]]##|[\+\-\$\+\*\/\%\^\<\>\?\&\|\!\;\=\~\,\[\]])*) REPLY=f${LINE:0:1} ;;
		(*) die unknown token start: ${(q)LINE:0:1} ;;
	esac

	LINE=${LINE:$mend[1]}
	return 0
}


# readonly -A arities=(${(z):-
# 	{P,R}\ 0 \
# 	{\`,O,E,B,C,Q,!,L,D,\,,A,\[,\],\~}\ 1 \
# 	{\-,\+,\*,\/,\%,\^,\?,\<,\>,\&,\|,\;,\=,W}\ 2 \
# 	{G,I}\ 3 \
# 	S\ 4})

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

typeset -ga asts
function generate_ast {
	next_token || return 1
	[[ $REPLY != f* ]] && return 0

	local i token=$REPLY arity=$arities[${REPLY#f}]
	for (( i = 1; i <= arity; i++ )); do
		generate_ast || die missing argument $i for function \'${token:1:2}\'
		token="$token$FS$REPLY"
	done

	asts+=($token)
	REPLY=A$#asts
	return 0
}

function eval_kn {
	LINE=${1?}
	generate_ast || die no program given
	run $REPLY
}

typeset -g match mbegin mend
setopt warncreateglobal
typeset -gA variables
function run {
	typeset -g REPLY
	
	if [[ ${1:0:1} = i ]]; then
		[[ -v variables[$1] ]] || die unknown variable ${1#i}
		# (( $+variables[$1] )) || die unknown variable ${1#i}
		REPLY=$variables[$1]
		return 0
	elif [[ ${1:0:1} != A ]] ; then
	# elif (( ! $+asts[$1] )); then
		REPLY=$1
		return 0
	fi

	local i=$IFS
	IFS=$FS
	set -- ${=asts[${1#A}]#f}
	IFS=$i
	local fn=$1
	shift

	case $fn in
		B) REPLY=$1; return 0;;
		=) run $2; variables[$1]=$REPLY; return 0 ;;
		\&) run $1; to_bool $REPLY && run $2; return 0 ;;
		\|) run $1; to_bool $REPLY || run $2; return 0 ;;
		W) while run $1; to_bool $REPLY; do run $2; done; REPLY=N; return 0 ;;
		I) run $1; if to_bool $REPLY; then run $2; else run $3; fi; return 0 ;;
	esac

	local -a a
	local arg
	for arg; do
		run $arg
		a+=$REPLY
	done
	set -- $a

	case $fn in
		# ARITY 0
		R) REPLY=n$RANDOM ;;
		P) read -r REPLY; REPLY=s${REPLY%%$'\r'#} ;;

		# ARITY 1
		C) run $1 ;;
		E) to_str $1; eval_kn $REPLY ;;
		\~) to_num $1; REPLY=n$((-REPLY)) ;;
		\$) to_str $1; REPLY=s$($=REPLY) ;;
		!) if to_bool $1; then REPLY=F; else REPLY=T; fi ;;
		Q) to_num $1; exit $REPLY ;;
		L) case $1 in
			s*) REPLY=n${#1#s} ;;
			a*) REPLY=n$arrays[$1] ;;
			*) to_ary $1; REPLY=n$#reply ;;
		esac ;;
		D) dump $1; REPLY=$1 ;;
		O) to_str $1; if [[ $REPLY = *\\ ]]; then print -rn -- ${REPLY%?}; else print -r -- $REPLY; fi ;;
		,) new_ary $1 ;;
		A) die TODO::: $fn ;;
		\[) to_ary $1; REPLY=$reply[1] ;;
		\]) case $1 in
			s*) REPLY=s${1:2} ;;
			*) to_ary $1; shift reply; new_ary $reply ;;
		esac ;;

		# ARITY 2
		\;) REPLY=$2 ;;
		+) case $1 in
			n*) to_num $2; REPLY=n$((${1#?} + REPLY)) ;;
			s*) to_str $2; REPLY=s${1#?}$REPLY ;;
			a*)
				to_ary $1
				local old=($reply)
				to_ary $2
				new_ary $old $reply ;;
			*) die unknown argument to $fn: $1
		esac ;;
		-) to_num $2; REPLY=n$((${1#?} - REPLY)) ;;
		\*) case $1 in
			n*) to_num $2; REPLY=n$((${1#?} * REPLY)) ;;
			s*) to_num $2; set -- ${1#s}; REPLY=s${(pl:$((${#1} * REPLY))::$1:)} ;;
			a*) to_ary $1; to_num $2
				local -a ary
				local i=
				for (( i = 0; i < $REPLY; i++ )); do
					ary+=($reply)
				done
				new_ary $ary ;;
			*) die unknown argument to $fn: $1
		esac ;;
		/) to_num $2; REPLY=n$((${1#?} / REPLY)) ;;
		%) to_num $2; REPLY=n$((${1#?} % REPLY)) ;;
		\^) case $1 in
			n*) to_num $2; REPLY=n$((${1#?} ** REPLY)) ;;
			a*) to_str $2; to_ary $1; ajoin "$REPLY" $reply; REPLY=s$REPLY ;; # TODO: whyis reply quoted here??
			*) die unknown argument to $fn: $1
		esac ;;
		\?) if eql $1 $2; then REPLY=T; else REPLY=F; fi ;;
		\<) compare $1 $2; if (( REPLY < 0 )) then REPLY=T; else REPLY=F; fi ;;
		\>) compare $1 $2; if (( REPLY > 0 )) then REPLY=T; else REPLY=F; fi ;;
		G) case $1 in
			s*) to_num $2
				local start=$REPLY
				to_num $3
				REPLY=s${${1#s}:$start:$REPLY} ;;
			a*) to_ary $1
				to_num $2; shift $REPLY reply
				to_num $3; shift -p $(($#reply - REPLY)) reply
				new_ary $reply ;;
			*) die unknown argument to $fn: $1 ;;
			esac ;;
		S) case $1 in
			s*) to_num $2; local start=$REPLY
				to_num $3; local len=$REPLY
				to_str $4
				REPLY=${1:0:$((start+1))}$REPLY${1:$((start+1+len))} ;;
			a*) to_ary $1; local answer=($reply)
				to_num $2; local start=$REPLY
				to_num $3; local len=$REPLY
				to_ary $4;
				answer[$((start+1)),$((start+len))]=($reply)
				new_ary $answer ;;
			*) die unknown argument to $fn: $1 ;;
			esac ;;
		*) die unknown function $fn ;;
	esac
	return 0
}

if [[ $1 = -e ]]; then
	eval_kn $2
else
	eval_kn "$(<$2)"
fi
