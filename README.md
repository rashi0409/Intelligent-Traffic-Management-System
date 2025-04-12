# Intelligent-Traffic-Management-System
## Traffic Light System
This project implements a simple, intelligent traffic light control system for managing four directional paths. It communicates with MATLAB via USB to receive real-time car counts and uses an LCD to display updates during the control cycle. The logic ensures fair path selection and avoids giving the green signal to the same path twice in a row unless necessary.

## Project Overview:
The system controls traffic flow for four defined routes:
A2B (Index 0)
B2A (Index 1)
C2D (Index 2)
D2C (Index 3)

Car counts for each path are sent from MATLAB in a line-by-line format. The microcontroller reads this input, updates internal counts, and uses a selection strategy to assign the green signal to the path with the highest number of waiting cars — with one condition: the same path is not allowed to be selected in consecutive cycles.
After each green cycle (fixed to 3 seconds), the car count is updated, assuming up to 5 cars have moved through. The process repeats until no cars remain.

## Features:
USB UART communication with MATLAB.
Real-time decision-making based on car density.
Skips previously selected path for fairness.
LCD output showing car counts and green-lighted direction.
Cycle-based simulation with consistent updates and status messages.

## How It Works
1. Receive Car Counts
 MATLAB sends strings like A2B,10 or D2C,5. Each line represents the number of cars waiting on a path.
2. End of Input
When END is received, the microcontroller processes the collected data.

3.  Display on LCD
Car counts are displayed for all four paths, split over two lines of the LCD:
A2B 10, B2A 4
C2D 6, D2C 3

4. Traffic Control Loop
The system:
Selects the path with the most cars (excluding the previously selected one).
Displays the active green path.
Sends a message back to MATLAB with the format:
GreenPath:<index>,<cars moved>,<green time>,<cars remaining>
Updates internal car counts.
Repeats the process until all cars are cleared.

5.  Completion
Once all car counts reach zero, a "DONE" message is sent to MATLAB, and the LCD displays All Clear.

6.  LCD Output Format:
1. While updating car count:
Car Counts:

A2B 5, B2A 3
C2D 2, D2C 1

2. During Green Cycle:
Green Path:
C2D

## Technical Summary
Fixed green signal duration: 3 seconds
Maximum cars passed per cycle: 5
Four directional paths handled
Previous path is skipped during selection if alternatives exist
Communication through USB UART
Integrated with MATLAB for input/output

## Requirements
PSoC or compatible microcontroller with:
USBUART component
2-line LCD display
MATLAB (for sending and receiving data via USB)
Embedded C environment (e.g., PSoC Creator)
