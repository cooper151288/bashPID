#!/bin/bash
#A PID fan controller
#Depenencies: bash, GNU bc
#Matt Cooper, 2015
# TODO: config file, generic sensor/cdev
# -The initialisation part looks like it would
#  be better off in a .conf
#
# - should be easy enough to make sensor/cdev
#   path and min/max vars superIO chip
#   name may be useful as most users pwms
#   and enable flags are there
#
#
# - ACPI and cpufreq throttling look like they
#   can be implemented here in the same fashion
#
#
# - Would precision timing be better? Code
#   assumes that calculation time is negligible,
#   could use date time to give system time in ns
#   and put that as dt in calcs
#
#DESIRED: online tuning and autotune
################initialisation:

dt=0.5        # Time base
p1=0.05       # unit is pwm/millidegree
p2=0.05
i1=0.005      # pwm seconds per millidegree
i2=0.005
d1=0.00025
d2=0.00025
s=10000       # Set point (millidegrees)
#smax=30000 
#smin=0
#expand to one per sensor per cdev
pwm_min1=70
pwm_min2=20
pwm_max1=255
pwm_max2=255                 #swap out for cdev naming convention next
#cdev1min=70
#cdev1max=255
#cdev1mintrip=10000          # below this temp cedevstate=cdevmin
#cedv1maxtrip                # max at this temp regardless of OP
#cdev2min=20
#cdev2max=255
#cdev2mintrip
#cdev2maxtrip
half=0.5
C1=73      # controller bias values (Integration constants)
C2=11      #
I1max=255  # Max value of integrator 1
I1min=-20  # Min value of integrator 1
I1init=50  # initial value of integrator 1
I2max=255  # Max value of integrator 2
I2min=-20  # Min value of integrator 2
I2init=20  # initial value of integator 2
Tmax=30000        #Max temperature, disable pwms (or whatever to get full fanspeed), sleep
#Tmaxcmd     #additional command to run when Tmax reched 
Tmaxhyst=15000    #Hysteresis value for Tmax. Script starts from beginning once reached
#Tmaxhystcmd #additional command to run when Tmaxhyst reached
#SuperIo=/sys/devices/platform/it87.552           #store SuperIo path to make it easier to read and write for devices
#cdev1path=$SuperIo/pwm1
#cdev1en=$SuperIo/pwm1_enable
#cdev2path=$SuperIo/pwm3
#cdev2en=$SuperIo/pwm3_enable
#fan=$SuperIo/fan1_input
#temp1=/sys/devices/pci0000:00/0000:00:18.3/hwmon/hwmon2/temp1_input
######################################################################
echo 1 > /sys/devices/platform/it87.552/pwm1_enable &           #enable pwm
echo 1 > /sys/devices/platform/it87.552/pwm3_enable &          #enable pwm
wait

#echo 255 > /sys/devices/platform/it87.552/pwm1 &           #set initial pwm here
#echo 255 > /sys/devices/platform/it87.552/pwm3 &           #set initial pwm here
#sleep 5                                                    #use if you want a running start
pwm_old1=$(cat /sys/devices/platform/it87.552/pwm1)                           #setup pwm_old
pwm_old2=$(cat /sys/devices/platform/it87.552/pwm3)                           #setup pwm_old
pwm_raw1=$pwm_old1                                                            #setup raw pwm
pwm_raw2=$pwm_old2

##set up old temps - only needed for weighted average derivative
T5=$(cat /sys/devices/pci0000:00/0000:00:18.3/hwmon/hwmon2/temp1_input)
E5=$(($T5 - $s))
#sleep $dt

T4=$(cat /sys/devices/pci0000:00/0000:00:18.3/hwmon/hwmon2/temp1_input)
E4=$(($T4 - $s))
#sleep $dt

T3=$(cat /sys/devices/pci0000:00/0000:00:18.3/hwmon/hwmon2/temp1_input)
E3=$(($T3 - $s))
#sleep $dt

T2=$(cat /sys/devices/pci0000:00/0000:00:18.3/hwmon/hwmon2/temp1_input)
E2=$(($T2 - $s))
#sleep $dt

T1=$(cat /sys/devices/pci0000:00/0000:00:18.3/hwmon/hwmon2/temp1_input)
E1=$(($T1 - $s))
#sleep $dt

T0=$(cat /sys/devices/pci0000:00/0000:00:18.3/hwmon/hwmon2/temp1_input)
E0=$(($T0 - $s))

I1=$I1init
I2=$I2init
##begin main loop

while [ $T0 -lt $Tmax ] #break loop when T>Tmax
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
##################################console output for user
clear
date
echo s = $s
echo pwm1 $(cat /sys/devices/platform/it87.552/pwm1)
echo pwm2 $(cat /sys/devices/platform/it87.552/pwm3)
echo Fan Speed = $(cat /sys/devices/platform/it87.552/fan1_input) 
echo pwm_raw1 = $pwm_raw1 pwm_raw2 = $pwm_raw2
echo P1 = $P1, P2 = $P2, I1 = $I1, I2 = $I2, D1 = $D1, D2 = $D2
echo O1 = $O1 O2 = $O2
echo T5 = $T5 T4 = $T4 T3 = $T3 T2 = $T2 T1 = $T1 T0 = $T0
echo E5 = $E5 E4 = $E4 E3 = $E3 E2 = $E2 E1 = $E1 E0 = $E0
echo pwm_new1 = $pwm_new1 pwm_new2 = $pwm_new2
##################################################


###########PID part-do for both sets of constants
#Integral - trapezium rule with min/max values
I1=$(echo "(($i1 * $dt * $half * ($E0 + $E1)) + $I1 )" | bc -l)
I2=$(echo "(($i2 * $dt * $half * ($E0 + $E1)) + $I2 )" | bc -l)

#######min/max values to help with windup
I1int=$(echo "($I1 + 0.5)/1" | bc)               #now an integer
I2int=$(echo "($I2 + 0.5)/1" | bc)

if [ $I1int -gt $I1max ]
 then
 I1=$I1max
 elif [ $I1int -lt $I1min ]
 then
 I1=$I1min
 else
:
fi

if [ $I2int -gt $I2max ]
 then
 I2=$I2max
 elif [ $I2int -lt $I2min ]
 then
 I2=$I2min
 else
:
fi
########################


#(derivative- use simple definition)
#D= d * (err_last - err_now) / dt

#simple derivative
#D1=$(echo "$d1 *  $(($E0 - $E1)) / $dt" | bc -l)
#D2=$(echo "$d2 *  $(($E0 - $E1)) / $dt" | bc -l)

#weighted average
D1=$(echo "$d1 *  (($(($E0 - $E1)) / $dt) + $(($E0 - $E2)) / (4 * $dt) + $(($E0 - $E3)) / (6 * $dt) + $(($E0 - $E4)) / (8 * $dt) + $(($E0 - $E5)) / (10 * $dt))" | bc -l)
D2=$(echo "$d2 *  (($(($E0 - $E1)) / $dt) + $(($E0 - $E2)) / (4 * $dt) + $(($E0 - $E3)) / (6 * $dt) + $(($E0 - $E4)) / (8 * $dt) + $(($E0 - $E5)) / (10 * $dt))" | bc -l)

# Proportional term
P1=$(echo "$p1 * $E0" | bc -l)
P2=$(echo "$p2 * $E0" | bc -l)

#output O=P+I+D
O1=$(echo "$P1 + $I1 + $D1" | bc -l)
O2=$(echo "$P2 + $I2 + $D2" | bc -l)

pwm_raw1=$(echo "$C1 + $O1" | bc -l) # add the constants in
pwm_raw2=$(echo "$C2 + $O2" | bc -l) #

pwm_new1=$(echo "($pwm_raw1 + 0.5)/1" | bc) #now an integer
pwm_new2=$(echo "($pwm_raw2 + 0.5)/1" | bc)

if [ $pwm_new1 -gt $pwm_max1 ]
 then
 pwm_new1=$pwm_max1
 pwm_raw1=$pwm_max1
 elif [ $pwm_new1 -lt $pwm_min1 ]
 then
 pwm_new1=$pwm_min1
 pwm_raw1=$pwm_min1
 else
:
fi


if [ $pwm_new2 -gt $pwm_max2 ] 
 then
 pwm_new2=$pwm_max2
 pwm_raw2=$pwm_max2
 elif [ $pwm_new2 -lt $pwm_min2 ]  
 then
 pwm_new2=$pwm_min2
 pwm_raw2=$pwm_min2
 else
:
fi

echo $pwm_new1 > /sys/devices/platform/it87.552/pwm1 &          #these lines do the fanspeed
echo $pwm_new2 > /sys/devices/platform/it87.552/pwm3 &           #change. be careful.
wait
##write new values into old, then we can loop
pwm_old1=$(echo "($pwm_raw1 + $O1 + 0.5)/1" | bc) #need to call from these raw values
pwm_old2=$(echo "($pwm_raw2 + $O1 + 0.5)/1" | bc) #need to call from these raw values
 }
done

#loop broken for cooling and reinitialisation

echo Too hot, fans on max
echo $pwm_max1 > /sys/devices/platform/it87.552/pwm1 &          #these lines do the fanspeed
echo $pwm_max2 > /sys/devices/platform/it87.552/pwm3 &           #change. be careful.
echo 0 > /sys/devices/platform/it87.552/pwm1_enable
echo 0 > /sys/devices/platform/it87.552/pwm3_enable


until [ $T0 -lt $Tmaxhyst ]
  do sleep 1
  T0=$(cat /sys/devices/pci0000:00/0000:00:18.3/hwmon/hwmon2/temp1_input)
  echo T0 = $T0
done
exec $0 #start from the beginning when cool
