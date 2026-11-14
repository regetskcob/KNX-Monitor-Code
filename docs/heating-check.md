# Heating check per room

"Check heating" (`lib/ui/heating_check_screen.dart`,
`lib/model/heating_check.dart`) puts the actual temperature, the setpoint and
the valve of every room side by side and adds a verdict in plain words. It is
meant for people who are not electricians: it only reads what was heard on the
bus and says whom to ask.

## Which addresses count

Roles follow from the datapoint type and the name (German and English):

| Role | Type | Name contains |
| --- | --- | --- |
| Actual temperature | 9.001 | Ist, Temperatur, actual, temperature |
| Setpoint | 9.001 | Soll, setpoint |
| Valve | 5.001 or 1.x | Stellwert, Ventil, valve, control value |

Outdoor, flow, return, floor and boiler temperatures are left out. The room
comes from the object index (`ObjectIndex`), otherwise from the part of the
name before the role word. A room appears once it has a valve or at least two
roles.

## Verdicts

| Verdict | Condition | Who to ask |
| --- | --- | --- |
| All right | within 1 K of the setpoint | – |
| Heating | more than 1 K too cold, valve open | wait |
| Controller asks for no heat | more than 1 K too cold, valve at 0 % | electrician: operating mode, window contact, lock |
| Valve open, room does not warm up | too cold, valve at 50 % or more for 90 min, gain below 0.3 K | heating engineer: drive, hydraulics, channel assignment |
| Too warm, valve open anyway | more than 1 K too warm, valve above 0 % | electrician: swapped sensors or channels, emergency mode |
| Actual temperature missing | no actual temperature for 2 h | electrician: sensor or push button |
| Too few values | setpoint, actual value or valve not heard yet | let it listen longer |

The thresholds are in `HeatingLimits`. "Does not warm up" needs a recording
that reaches back 90 minutes; with less it stays "heating".

## Limits

Parameters in the devices, pressure, flow and stuck valves are not on the bus.
Many installations send setpoint and valve only on change, so a room can stay
at "too few values" until something changes.
