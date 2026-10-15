// Test séparé dans Arduino IDE : installer MD_Parola et MD_MAX72XX.
#include <MD_Parola.h>
#include <MD_MAX72xx.h>
constexpr uint8_t MODULES = 8; // Mettre 1 pour le premier test.
MD_Parola panel(MD_MAX72XX::FC16_HW,23,18,5,MODULES);
void setup() {
  Serial.begin(115200);
  panel.begin();
  panel.setIntensity(2);
  panel.displayText("TEST",PA_CENTER,65,0,PA_PRINT,PA_NO_EFFECT);
  Serial.println("Test fixe MAX7219 : DIN=23 CLK=18 CS=5");
}
void loop() { panel.displayAnimate(); }
