#!/bin/zsh


setopt extendedglob rcquotes #nounset
setopt NO_GLOBAL_EXPORT

RANDOM=$(date +%s)

die () { print ${ZSH_SCRIPT:t}: $@ >&2; exit 1 }
bug () die bug: $@
dbg () print $@
todo () die $@

to_str () case ${1-REPLY} in
	[sn]*) REPLY=${1:1} ;;
	T)     REPLY=true   ;;
	F)     REPLY=false  ;;
	N)     REPLY=       ;;
	a*) to_ary $1; ajoin $'\n' $reply ;;
	*) bug unknown type for to_str: $1 ;;
esac

typeset -gA arrays=(a0 0)
typeset -ga reply
typeset -g REPLY ARY_IDX FS=$'\x1C'
new_ary () {
	(( ! # )) && { REPLY=a0; return }
	local i len=$#
	arrays[${REPLY::=a$((++ARY_IDX))}]=$#
	for (( i = 0; i < $len; i++ )); do
		arrays[$REPLY$FS$i]=$1
		shift
	done
}

to_num () case ${1-REPLY} in
	# s[[:space:]]#([-+]|)<->) dbg yes ;;
	s*) REPLY=$(ruby -e 'puts $*[0].to_i' -- ${1#s});; # TODO
	n*)   REPLY=${1#?};;
	[FN]) REPLY=0 ;;
	T)    REPLY=1 ;;
	a*)   REPLY=$arrays[$1] ;;
	*) bug unknown type for to_num: $1 ;;
esac

to_bool () [[ ${1-REPLY} != (s|[na]0|[FN]) ]]

to_ary () case $1 in
	[FN]) reply=() ;;
	T) reply=(T) ;;
	a*) reply=(); while (( $#reply < $arrays[$1] )); do
		reply+=$arrays[$1$FS$#reply]; done ;;
	s*) set -- ${(s::)1#s}
		reply=()
		while (( # )); do reply+=s$1; shift; done ;;
	n*) 
		reply=()
		local i sign value=${1#n}
		if (( value < 0 )); then sign=-; ((value *= -1)); fi
		for (( i = 0; i < $#value; i++ )); do
			reply+=n$sign${value:$i:1}
		done ;;

	*) bug unknown type for to_ary: $1 ;;
esac
ajoin () {
	local sep=$1 result i
	(( # )) && shift
	(( # )) && {
		to_str $1
		result+=$REPLY
		shift
		for i; do
			result+=$sep
			to_str $i
			result+=$REPLY
		done
	}
	REPLY=$result
}

dump () case ${1-REPLY} in
	[TF]|n*) 
		local oldreply=$REPLY
		to_str $1; print -nr -- $REPLY
		REPLY=$oldreply;;
	N) print -n null ;;
	s*)
		local i=${1#s}
		i=${i//$'\\'/\\\\}
		i=${i//$'\n'/\\n}
		i=${i//$'\r'/\\r}
		i=${i//$'\t'/\\t}
		i=${i//$'\"'/\\\"}
		print -nr -- \"$i\" ;;
	a*) 
		print -n \[
		local i
		for (( i = 0; i < $arrays[$1]; i++ )); do
			(( i )) && print -n ', '
			dump $arrays[$1$FS$i]
		done
		print -n \] ;;
	*) bug unknown type for dump: $1
esac

eql () {
	[[ $1 == $2 ]] && return
	[[ ${1:0:1} != a || ${2:0:1} != a ]] && return 1
	(( $arrays[$1] != $arrays[$2] )) && return 1
	local i
	for (( i = 0; i < $arrays[$1]; i++ )); do
		eql $arrays[$1$FS$i] $arrays[$2$FS$i] || return 1
	done
	return 0
}

functions -M min 1 -1
min () {
	local arg min=$1
	shift
	for arg; do (( arg < min )) && min=$arg; done
	(( min ))
	:
}

functions -M cmp 2 2
cmp () { (( $1 < $2 ? -1 : $1 > $2 )); : }

compare () case $1 in
	s*) to_str $2; if [[ ${1#s} < $REPLY ]]; then REPLY=-1;
		elif [[ ${1#s} > $REPLY ]]; then REPLY=1; else REPLY=0; fi ;;
	n*) to_num $2; REPLY=$(( cmp(${1#n}, REPLY) )) ;;
	[TF]) to_num $1; local a=$REPLY; if to_bool $2; then REPLY=1; else REPLY=0; fi; compare n$a n$REPLY ;;
	a*)
		to_ary $2
		local -a rep=($reply)
		local i tmp min=$(( min($#reply, $arrays[$1]) ))
		for (( i = 1; i <= $min; i++ )); do
			compare $arrays[$1$FS$((i-1))] $rep[$i]
			(( REPLY )) && return
		done
		REPLY=$(( cmp(arrays[$1], $#rep) )) ;;
	*) bug unknown type for compare: $1
esac

typeset -g REPLY line

function next_token {
	# Strip leading whitespace and comments
	line=${line##(\#[^$'\n']#|[:()\{\}[:space:]]#)#}

	[[ -z $line ]] && return 1

	case $line in
		((#b)(<->)*)                     REPLY=n$match[1] ;;
		((#b)([_[:lower:][:digit:]]##)*) REPLY=i$match[1] ;;
		((#b)(\"[^\"]#\"|\'[^\']#\')*)   REPLY=s${${match#?}%?} ;;
		(@*) REPLY=a0 line=${line:1}; return 0 ;;
		((#b)([TFN][_[:upper:]]#)*)      REPLY=${line:0:1} ;;
		((#b)([_[:upper:]]##|[\+\-\$\+\*\/\%\^\<\>\?\&\|\!\;\=\~\,\[\]])*) REPLY=f${line:0:1} ;;
		(*) die unknown token start: ${(q)line:0:1} ;;
	esac

	line=${line:$mend[1]}
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
	line=${1?}
	generate_ast || die no program given
	dbg "reply: $REPLY"
	run $REPLY
}

typeset -g match mbegin mend
setopt warncreateglobal
typeset -gA variables
function run {
	typeset -g REPLY
	
	dbg "run: start: $@"

	if [[ ${1:0:1} = i ]]; then
		dbg "run: is a variable: $@"
		[[ -v variables[$1] ]] || die unknown variable ${1#i}
		# (( $+variables[$1] )) || die unknown variable ${1#i}
		REPLY=$variables[$1]
		return 0
	elif [[ ${1:0:1} != A ]] ; then
	# elif (( ! $+asts[$1] )); then
		dbg "run: not an ast: $@"
		REPLY=$1
		return 0
	fi

	local i=$IFS
	IFS=$FS
	set -- ${=asts[${1#A}]#f}
	IFS=$i
	local fn=$1
	shift
	dbg "[$fn] start: $@"

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
		dbg "[$fn] run: $arg"
		run $arg
		a+=$REPLY
	done
	set -- $a
	dbg "[$fn] after run: $@"

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
		D) dbg "{$1}"; dump $1; REPLY=$1 ;;
		O) to_str $1; if [[ $REPLY = *\\ ]]; then print -rn -- ${REPLY%?}; else print -r -- $REPLY; fi ;;
		,) new_ary $1 ;;
		A) todo $fn ;;
		\[) to_ary $1; REPLY=$reply[1] ;;
		\]) case $1 in
			s*) REPLY=s${1:2} ;;
			*) to_ary $1; shift reply; new_ary $reply ;;
		esac ;;

		# ARITY 2
		\;) dbg "{2=$2}"; REPLY=$2 ;;
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
	dbg "Done: $fn $REPLY"
	return 0
}

# line='O ; 1 2 '
# generate_ast
# dbg $asts[$REPLY]
# exit
dbg () :

if [[ $1 = -e ]]; then
	eval_kn $2
else
	eval_kn "$(<$2)"
fi
