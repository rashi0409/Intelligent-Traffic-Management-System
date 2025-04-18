#include "project.h"
#include <string.h>
#include <stdio.h>
#include <stdbool.h>

// Global variables
unsigned char rxBuffer[64];
int carCounts[4] = {0, 0, 0, 0};
int prevGreenPath = -1;  // Track the previous green path index

// Configuration parameters
const int speed = 5;      // cars per green cycle (3 s)
const int greenTime = 3;  // duration of green signal in seconds

// Array of path names (order must match MATLAB: A2B, B2A, C2D, D2C)
const char* paths[4] = {"A2B", "B2A", "C2D", "D2C"};

//-------------------------
// Function: parseData
void parseData(const char* data) {
    char localPath[10] = {0};
    int localCount = 0;
    sscanf(data, "%[^,],%d", localPath, &localCount);
    
    char debug[64];
    sprintf(debug, "Received: %s, Parsed: %s, %d\n", data, localPath, localCount);
    USBUART_PutString(debug);
    
    int index = -1;
    if (strcmp(localPath, "A2B") == 0) index = 0;
    else if (strcmp(localPath, "B2A") == 0) index = 1;
    else if (strcmp(localPath, "C2D") == 0) index = 2;
    else if (strcmp(localPath, "D2C") == 0) index = 3;
    
    if (index != -1) {
        carCounts[index] = localCount;
    } else {
        USBUART_PutString("Error: Unknown path!\n");
    }
}

//-------------------------
void displayCarCounts() {
    char line0[17] = {0};
    char line1[17] = {0};
    
    snprintf(line0, sizeof(line0), "%s %d, %s %d", 
             paths[0], carCounts[0],
             paths[1], carCounts[1]);
    snprintf(line1, sizeof(line1), "%s %d, %s %d", 
             paths[2], carCounts[2],
             paths[3], carCounts[3]);
    
    LCD_ClearDisplay();
    LCD_Position(0, 0);
    LCD_PrintString(line0);
    LCD_Position(1, 0);
    LCD_PrintString(line1);
}

//-------------------------
void displayInputData() {
    displayCarCounts();
    CyDelay(2000);
}

//-------------------------
// Modified to avoid selecting the same path consecutively
int getNextGreenPath() {
    int max = -1;
    int nextPath = -1;

    // First pass: try skipping the previous path
    for (int i = 0; i < 4; i++) {
        if (i == prevGreenPath) continue;
        if (carCounts[i] > max) {
            max = carCounts[i];
            nextPath = i;
        }
    }

    // Fallback: if skipping previous path gives no result, allow it
    if (nextPath == -1) {
        max = -1;
        for (int i = 0; i < 4; i++) {
            if (carCounts[i] > max) {
                max = carCounts[i];
                nextPath = i;
            }
        }
    }

    return (max <= 0) ? -1 : nextPath;
}

//-------------------------
void updateCarCount(int pathIndex) {
    int moved = (carCounts[pathIndex] < speed) ? carCounts[pathIndex] : speed;
    carCounts[pathIndex] -= moved;
}

//-------------------------
bool carsRemaining() {
    for (int i = 0; i < 4; i++) {
        if (carCounts[i] > 0)
            return true;
    }
    return false;
}

//-------------------------
void sendGreenStatus(int pathIndex) {
    int moved = (carCounts[pathIndex] < speed) ? carCounts[pathIndex] : speed;
    int remaining = carCounts[pathIndex] - moved;
    
    char msg[64];
    sprintf(msg, "GreenPath:%d,%d,%d,%d\n", pathIndex + 1, speed, greenTime, remaining);
    USBUART_PutString(msg);
}

//-------------------------
// Main Function
//-------------------------
int main(void) {
    CyGlobalIntEnable;
    LCD_Start();
    USBUART_Start(0, USBUART_5V_OPERATION);
    
    LCD_PrintString("Waiting USB...");

    while (!USBUART_GetConfiguration());
    USBUART_CDC_Init();
    
    for (;;) {
        // Step 1: Wait for full input from MATLAB
        bool fullInputReceived = false;
        while (!fullInputReceived) {
            if (USBUART_DataIsReady()) {
                uint16 count = USBUART_GetAll(rxBuffer);
                if (count >= sizeof(rxBuffer))
                    count = sizeof(rxBuffer) - 1;
                rxBuffer[count] = '\0';
                
                char debug[80];
                sprintf(debug, "Raw data: %s\n", rxBuffer);
                USBUART_PutString(debug);
                
                char* line = strtok((char*)rxBuffer, "\n");
                while (line != NULL) {
                    if (strcmp(line, "END") == 0) {
                        fullInputReceived = true;
                    } else {
                        parseData(line);
                    }
                    line = strtok(NULL, "\n");
                }
            }
            CyDelay(100);
        }

        // Step 2: Show received input
        displayInputData();
        CyDelay(1000);

        // Step 3: Run traffic cycles
        if (carsRemaining()) {
            while (carsRemaining()) {
                int pathIndex = getNextGreenPath();
                if (pathIndex == -1) break;

                LCD_ClearDisplay();
                LCD_Position(0, 0);
                LCD_PrintString("Green Path:");
                LCD_Position(1, 0);
                LCD_PrintString(paths[pathIndex]);

                sendGreenStatus(pathIndex);

                CyDelay(greenTime * 1000);

                updateCarCount(pathIndex);

                prevGreenPath = pathIndex;  // Track last used path

                CyDelay(500);
                displayCarCounts();
            }
        } else {
            USBUART_PutString("DONE\n");
            LCD_ClearDisplay();
            LCD_Position(0, 0);
            LCD_PrintString("All Clear");
            CyDelay(2000);
        }

        // Reset state for next input cycle
        carCounts[0] = carCounts[1] = carCounts[2] = carCounts[3] = 0;
        prevGreenPath = -1;
    }
}
