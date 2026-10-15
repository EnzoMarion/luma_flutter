#pragma once
#include <Arduino.h>
void displayBegin();
void displayTick();
bool applyCommand(char kind, const char* payload);
