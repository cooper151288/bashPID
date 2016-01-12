#!/bin/bash
#A PID fan controller
#Depenencies: bash, GNU bc
#Matt Cooper, 2015
# TODO: config file, generic sensor/cdev
# - should be easy enough to make sensor/cdev
#   path and min/max vars superIO chip
#   name may be useful as most users pwms
#   and enable flags are there
# - ACPI and cpufreq throttling look like they
#   can be implemented here in the same fashion
# - Would precision timing be better? Code
#   assumes that calculation time is negligible,
#   could use date time to give system time in ns
#   and put that as dt in calcs
#
#DESIRED: online tuning and autotune
#
################initialisation:
dt=0.25
p1=0.125   # unit is pwm/millidegree
p2=0.25    # dt invariant
i1=0.002   # pwm seconds per millidegree
i2=0.001   # each step is proportional to dt
d1=0.0005
d2=0.0005
s=10000
#expand to one per sensor per cdev
pwm_min1=70
#cdev1min=70
#cdev1max=255
#cdev1mintrip=10000 # below this temp cedevstate=cdevmin
#cdev2min=20
#cdev2max=255
pwm_min2=20
pwm_max1=255
pwm_max2=255
#swap out for cdev naming convention
half=0.5
C1=50 # controller bias values
C2=30
#I term needs min, max to prevent windup
#Tmax        #Max temperature, disable pwms (or whatever to get full fanspeed), sleep
#Tmaxcmd     #additional command to run when Tmax reched 
#Tmaxhyst    #Hysteresis value for Tmax
#Tmaxhystcmd #additional command to run when Tmaxhyst reached
#SuperIo=/sys/devices/platform/it87.552           #store SuperIo path to make it easier to read and write for devices
#cdev1path=$SuperIo/pwm1
#cdev1en=$SuperIo/pwm1_enable
#cdev2path=$SuperIo/pwm3
#cdev2en=$SuperIo/pwm3_enable
#fan=$SuperIo/fan1_input
#temp1=/sys/devices/pci0000:00/0000:00:18.3/hwmon/hwmon2/temp1_input



echo 1 > /sys/devices/platform/it87.552/pwm1_enable &           #enable pwm
echo 1 > /sys/devices/platform/it87.552/pwm3_enable &          #enable pwm

wait

#echo 255 > /sys/devices/platform/it87.552/pwm1 &           #set initial pwm here
#echo 255 > /sys/devices/platform/it87.552/pwm3 &         #set initial pwm here
#echo pwm1 value
#cat /sys/devices/platform/it87.552/pwm1
#echo pwm3 value
#cat /sys/devices/platform/it87.552/pwm3
#sleep 5                                                                      #use if you want a running start
pwm_old1=$(cat /sys/devices/platform/it87.552/pwm1)                           #setup pwm_old
pwm_old2=$(cat /sys/devices/platform/it87.552/pwm3)                           #setup pwm_old
pwm_raw1=$pwm_old1                                                            #setup raw pwm
pwm_raw2=$pwm_old2

##set up old temps
T5=$(cat /sys/devices/pci0000:00/0000:00:18.3/hwmon/hwmon2/temp1_input)
E5=$(($T5 - $s))
sleep $dt

T4=$(cat /sys/devices/pci0000:00/0000:00:18.3/hwmon/hwmon2/temp1_input)
E4=$(($T4 - $s))
sleep $dt

T3=$(cat /sys/devices/pci0000:00/0000:00:18.3/hwmon/hwmon2/temp1_input)
E3=$(($T3 - $s))
sleep $dt

T2=$(cat /sys/devices/pci0000:00/0000:00:18.3/hwmon/hwmon2/temp1_input)
E2=$(($T2 - $s))
sleep $dt

T1=$(cat /sys/devices/pci0000:00/0000:00:18.3/hwmon/hwmon2/temp1_input)
E1=$(($T1 - $s))
sleep $dt

T0=$(cat /sys/devices/pci0000:00/0000:00:18.3/hwmon/hwmon2/temp1_input)
E0=$(($T0 - $s))

I1=0
I2=0
##begin main loop

while :
       do {
          T5=$T4
          T4=$T3
          T3=$T2
          T2=$T1
          T1=$T0
          E5=$(($T5 - $s))
          E4=$(($T4 - $s))
          E3=$(($T3 - $s))
          E2=$(($T2 - $s))
          E1=$(($T1 - $s))
#########
sleep $dt
#########
       T0=$(cat /sys/devices/pci0000:00/0000:00:18.3/hwmon/hwmon2/temp1_input)
       E0=$(($T0 - $s))
##temp functions now stored
clear
date
echo pwm1
cat /sys/devices/platform/it87.552/pwm1
echo pwm2
cat /sys/devices/platform/it87.552/pwm3
echo Fan Speed = $(cat /sys/devices/platform/it87.552/fan1_input)
echo pwm_raw1 = $pwm_raw1 pwm_raw2 = $pwm_raw2
echo P1 = $P1, P2 = $P2, I1 = $I1, I2 = $I2, D1 = $D1, D2 = $D2
echo O1 = $O1 O2 = $O2
echo T5 = $T5 T4 = $T4 T3 = $T3 T2 = $T2 T1 = $T1 T0 = $T0
echo E5 = $E5 E4 = $E4 E3 = $E3 E2 = $E2 E1 = $E1 T0 = $E0
echo pwm_new1 = $pwm_new1 pwm_new2 = $pwm_new2

###########PID part-do for both sets of constants

#(integral- use trapezium rule)
#lets do the integrals recursively; less math, more info
#I1=$(echo "($i1 * $dt * $half * ($E0 + $E5) + $i1 * $dt * ($E1 + $E2 + $E3 + $E4))" | bc -l)
#I2=$(echo "($i2 * $dt * $half * ($E0 + $E5) + $i1 * $dt * ($E1 + $E2 + $E3 + $E4))" | bc -l)

I1=$(echo "(($i1 * $dt * $half * ($E0 + $E1)) + $I1 )" | bc -l)
I2=$(echo "(($i2 * $dt * $half * ($E0 + $E1)) + $I2 )" | bc -l)

#(derivative- use simple definition)
#D= d * (err_last - err_now) / dt
#could try weighted avg over available points

D1=$(echo "$d1 *  (($(($E0 - $E1)) / $dt) + $(($E0 - $E2)) / (4 * $dt) + $(($E0 - $E3)) / (6 * $dt) + $(($E0 - $E4)) / (8 * $dt) + $(($E0 - $E5)) / (10 * $dt))" | bc -l)
D2=$(echo "$d2 *  (($(($E0 - $E1)) / $dt) + $(($E0 - $E2)) / (4 * $dt) + $(($E0 - $E3)) / (6 * $dt) + $(($E0 - $E4)) / (8 * $dt) + $(($E0 - $E5)) / (10 * $dt))" | bc -l)

#P= p * err_new
#P1=$(echo "$p1 *  ($E0 * 6 + $E1 * 5 + $E2 * 4 + $E3 * 3 + $E4 * 2 + $E5 * 1)" | bc -l)
#P2=$(echo "$p2 *  ($E0 * 6 + $E1 * 5 + $E2 * 4 + $E3 * 3 + $E4 * 2 + $E5 * 1)" | bc -l)
P1=$(echo "$p1 * $E0" | bc -l)
P2=$(echo "$p2 * $E0" | bc -l)

#output O=P+I+D
O1=$(echo "$P1 + $I1 + $D1" | bc -l)
O2=$(echo "$P2 + $I2 + $D2" | bc -l)

#pwm_old + O = pwm_new. This is a rate equation as the pwm increases by O every dt
#pwm_raw1=$(echo "$pwm_raw1 + $O1" | bc -l)
#pwm_raw2=$(echo "$pwm_raw2 + $O2" | bc -l)

pwm_raw1=$(echo "$C1 + $O1" | bc -l)
pwm_raw2=$(echo "$C2 + $O2" | bc -l)

pwm_new1=$(echo "($pwm_raw1 + 0.5)/1" | bc) #now an integer
pwm_new2=$(echo "($pwm_raw2 + 0.5)/1" | bc)

#echo rounded pwm1 value is $pwm_new1  #now integer####use if statement to correct the value
#echo rounded pwm2 value is $pwm_new2  #must be 0-255

if [ $pwm_new1 -gt $pwm_max1 ]
 then
 pwm_new1=$pwm_max1
 pwm_raw1=$pwm_max1
# s=$(echo "$s + $O1" | bc)
 elif [ $pwm_new1 -lt $pwm_min1 ]
 then
 pwm_new1=$pwm_min1
 pwm_raw1=$pwm_min1
# s=$(echo "$s - $O1 - 250" | bc)
 else
:
fi


if [ $pwm_new2 -gt $pwm_max2 ] 
 then
 pwm_new2=$pwm_max2
 pwm_raw2=$pwm_max2
# s=$(echo "($s + $O2)" | bc)  
 elif [ $pwm_new2 -lt $pwm_min2 ]  
 then
 pwm_new2=$pwm_min2
 pwm_raw2=$pwm_min2
# s=$(echo "$s - $O2 -250" | bc)
 else
: #echo no overshoot
fi

s=$(echo "($s + 0.5)/1" | bc)

echo $pwm_new1 > /sys/devices/platform/it87.552/pwm1           #these lines do the fanspeed
echo $pwm_new2 > /sys/devices/platform/it87.552/pwm3           #change. be careful.

##write new values into old, then we can loop
pwm_old1=$(echo "($pwm_raw1 + $O1 + 0.5)/1" | bc) #need to call from these raw values
pwm_old2=$(echo "($pwm_raw2 + $O1 + 0.5)/1" | bc) #need to call from these raw values
};
done
