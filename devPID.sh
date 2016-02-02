#!/bin/bash
#A PID fan controller
#Depenencies: bash, GNU bc
#Matt Cooper, 2015
# TODO: -more arrays, functions, timing using nanosecond times
#       -parallel execution
#
# - Improved cpufreq support!
#
# - Would precision timing be better? Code
#   assumes that calculation time is negligible,
#   could use date time to give system time in ns
#   and put that as dt in calcs
#
#DESIRED: online tuning and autotune
################initialisation:
source config
for z in $(seq 0 $cores)
do cpufreq-set -c $z -g $gov_restart -u ${freq_list[0]}
done
echo 1 > $pwm1en &           #enable pwm
echo 1 > $pwm2en &           #enable pwm
wait

#echo 255 > $pwm1path &                             #set initial pwm here
#echo 255 > $pwm2path &                             #set initial pwm here
#sleep 5                                            #use if you want a running start
pwm_old1=$(cat $pwm1path)                           #setup pwm_old
pwm_old2=$(cat $pwm2path)                           #setup pwm_old
pwm_raw1=$pwm_old1                                  #setup raw pwm
pwm_raw2=$pwm_old2
##set up old temps - only needed for weighted average derivative
for a in {5..0}; 
  do export T$a=$(cat $temp1)
  done
T=($(cat $temp1) $(cat $temp1) $(cat $temp1) $(cat $temp1) $(cat $temp1) $(cat $temp1) )

O1=$C1
O2=$C2
O=($C1 $C2)
I1=$I1init
I2=$I2init
I=($I1init $I2init)
##begin main loop

while [ $T0 -lt $Tmax ] #break loop when T>Tmax
       do {
          T5=$T4
         T4=$T3
        T3=$T2
       T2=$T1
      T1=$T0
#      for x in {5..1}
#      do : 
#      T[$x]=${T[$(($x - 1))]}
#      done
time[0]=$(date '+%S%N')
#########
sleep $dt
#########
#clear
       T0=$(cat $temp1)
##temp functions now stored
##################################console output for user
date
echo setpoints are ${s[*]}
#echo -e "setpoints" ${$s[*]} "\n" "pwm1" $(cat $pwm1path) "pwm2" $(cat $pwm2path) "\n"
echo pwm1 $(cat $pwm1path) pwm2 $(cat $pwm2path)
echo pwm_new1 = $pwm_new1 pwm_new2 = $pwm_new2
echo Fan Speed = $(cat $SuperIo/fan1_input) 
#echo pwm_raw1 = $pwm_raw1 pwm_raw2 = $pwm_raw2
echo P1 = $P1, P2 = $P2, I1 = $I1, I2 = $I2, D1 = $D1, D2 = $D2
#echo O1 = $O1 O2 = $O2
#echo T5 = $T5 T4 = $T4 T3 = $T3 Ts1 = $s1 s2= $s22 = $T2 T1 = $T1 T0 = $T0
#echo E5 = $E5 E4 = $E4 E3 = $E3 E2 = $E2 E1 = $E1 E0 = $E0
echo T0 = $T0
##################################################
#if [[ $T0 -lt $pwm1_mintrip  && T0 -lt $pwm2_mintrip ]]
#  then
#  continue
#fi
###########PID part-do for both sets of constants
###################pwm1######################
if [ $T0 -gt $pwm1_maxtrip ]
 then
 pwm_new1=$pwm_max1_1
 pwm_raw1=$pwm_max1_1
 I1=$I1max
 elif [ $T0 -lt $pwm1_mintrip ]
 then
 pwm_new1=$pwm_min1_1
 pwm_raw1=$pwm_min1_1
 else

{
          E5=$(($T5 - $s1))
          E4=$(($T4 - $s1))
          E3=$(($T3 - $s1))
          E2=$(($T2 - $s1))
          E1=$(($T1 - $s1))
          E0=$(($T0 - $s1))
         # E[0]=($E5 $E4 $E3 $E2 $E1 $E0)
#Integral - trapezium rule with min/max values
I1=$(echo "(($i1 * $dt * $half * ($E0 + $E1)) + $I1 )" | bc -l)
I1int=$(echo "($I1 + 0.5)/1" | bc)               #now an integer
if [ $I1int -gt $I1max ]
  then
  I1=$I1max
  elif [ $I1int -lt $I1min ]
  then
  I1=$I1min
  else
  :
fi
echo $I1 > data/I1 &
#(derivative- use simple definition)
#D= d * (err_last - err_now) / dt
#simple derivative
#D1=$(echo "$d1 *  $(($E0 - $E1)) / $dt" | bc -l)
#weighted average
D1=$(echo "$d1 * (($(($E0 - $E1)) / $dt) + $(($E0 - $E2)) / (4 * $dt) + $(($E0 - $E3)) / (6 * $dt) + $(($E0 - $E4)) / (8 * $dt) + $(($E0 - $E5)) / (10 * $dt))" | bc -l)
# Proportional term
P1=$(echo "$p1 * $E0" | bc -l)
O1=$(echo "$P1 + $I1 + $D1" | bc -l)
pwm_raw1=$(echo "$C1 + $O1" | bc -l) # add the constants in
pwm_new1=$(echo "($pwm_raw1 + 0.5)/1" | bc) #now an integer
if [ $pwm_new1 -gt $pwm_max1_1 ]
 then
 pwm_new1=$pwm_max1_1
 pwm_raw1=$pwm_max1_1
 elif [ $pwm_new1 -lt $pwm_min1_1 ]
 then
 pwm_new1=$pwm_min1_1
 pwm_raw1=$pwm_min1_1
 else
:
fi
pwm_old1=$(echo "($pwm_raw1 + $O1 + 0.5)/1" | bc) #need to call from these raw values
 }
fi
echo $pwm_new1 > $pwm1path &          #these lines do the fanspeed
date '+%S%N'
########################end of pwm1################
##############################pwm2#################
if [ $T0 -gt $pwm2_maxtrip ]
 then
 pwm_new2=$pwm_max2_1
 pwm_raw2=$pwm_max2_1
 I2=$I2max
 elif [ $T0 -lt $pwm2_mintrip ]
 then
 pwm_new2=$pwm_min2_1
 pwm_raw2=$pwm_min2_1
 echo $pwm_new2 > $pwm2path &
 #continue
 else

{
          E5=$(($T5 - $s2))
          E4=$(($T4 - $s2))
          E3=$(($T3 - $s2))
          E2=$(($T2 - $s2))
          E1=$(($T1 - $s2))
          E0=$(($T0 - $s2))
I2=$(echo "(($i2 * $dt * $half * ($E0 + $E1)) + $I2 )" | bc -l)
I2int=$(echo "($I2 + 0.5)/1" | bc)
if [ $I2int -gt $I2max ]
 then
 I2=$I2max
 elif [ $I2int -lt $I2min ]
 then
 I2=$I2min
 else
:
fi
echo $I2 > data/I2 &
#D2=$(echo "$d2 *  $(($E0 - $E1)) / $dt" | bc -l)
D2=$(echo "$d2 *  (($(($E0 - $E1)) / $dt) + $(($E0 - $E2)) / (4 * $dt) + $(($E0 - $E3)) / (6 * $dt) + $(($E0 - $E4)) / (8 * $dt) + $(($E0 - $E5)) / (10 * $dt))" | bc -l)
P2=$(echo "$p2 * $E0" | bc -l)
#output O=P+I+D
O2=$(echo "$P2 + $I2 + $D2" | bc -l)
pwm_raw2=$(echo "$C2 + $O2" | bc -l) #
pwm_new2=$(echo "($pwm_raw2 + 0.5)/1" | bc)
if [ $pwm_new2 -gt $pwm_max2_1 ]
 then
 pwm_new2=$pwm_max2_1
 pwm_raw2=$pwm_max2_1
 elif [ $pwm_new2 -lt $pwm_min2_1 ]
 then
 pwm_new2=$pwm_min2_1
 pwm_raw2=$pwm_min2_1
 else
:
fi
pwm_old2=$(echo "($pwm_raw2 + $O2 + 0.5)/1" | bc)
 }
fi
echo $pwm_new2 > $pwm2path &           #change. be careful.
date '+%S%N'
{ : 
################################end of pwm2##################
 }

 
 }
done
#if [ $T0 -le $Thot ]

#loop broken for cooling and reinitialisation

echo Too hot, fans on max
#for z in {0..7}
#do cpufreq-set -c $z -g $gov_throttle
#done
echo $pwm_max1 > $pwm1path &
echo $pwm_max2 > $pwm2path &
echo 0 > $pwm1en
echo 0 > $pwm2en


until [ $T0 -lt $Tmaxhyst ]
  do :
  { 
  T0=$(cat $temp1)
     echo temp $T0
             K=$(($T0 - $Thot))
             j=$(($K / $Tstep))
                 if [ $j -ge $numfreq ]
                  then
                   j=$numfreq
                 elif [ $j -le 0 ]
                  then
                   j=0
                 fi
    t=$(echo "$dtsave / (2^$j)" | bc -l) #poll faster when throttling
    echo new j $j
    echo new freq ${freq_list[$j]}
    for z in $(seq 0 $cores)
      do cpufreq-set -c $z -u ${freq_list[$j]}
    done
 sleep $t
 }
done
sleep $coolsleep
exec $0 #start from the beginning when cool. the config will apply changes too.
