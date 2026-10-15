#include <Arduino.h>
#include "display.h"
#include "ble_link.h"

void setup() {
  Serial.begin(115200);
  displayBegin();
  bleBegin();
  Serial.println("Luma v1 : prêt, DIN=23 CLK=18 CS=5, 64x8 si MODULES=8");
}
void loop() {
  bleTick();
  displayTick();
  // Aucun délai bloquant : Parola règle le rythme de l'animation.
  yield();
}
