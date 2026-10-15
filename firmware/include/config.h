#pragma once
#include <MD_MAX72xx.h>

// 0 = panneau rouge MAX7219, 1 = matrice couleur WS2812B 8x8.
#ifndef LUMA_PANEL_COLOR
#define LUMA_PANEL_COLOR 0
#endif
// Commencer avec 1, puis passer à 8 après validation du câblage.
constexpr uint8_t MODULES = 8;
constexpr uint8_t PIN_DIN = 23;
constexpr uint8_t PIN_CLK = 18;
constexpr uint8_t PIN_CS = 5;
constexpr uint8_t PIN_RGB = 4;
constexpr uint8_t RGB_WIDTH = 8;
constexpr uint8_t RGB_HEIGHT = 8;
// Hypothèse à vérifier sur les modules réellement achetés.
constexpr auto HARDWARE = MD_MAX72XX::FC16_HW;
constexpr char SERVICE_UUID[] = "7c8d0001-5b7a-4e9e-9f31-9e8c28480a01";
constexpr char WRITE_UUID[] = "7c8d0002-5b7a-4e9e-9f31-9e8c28480a01";
constexpr char NOTIFY_UUID[] = "7c8d0003-5b7a-4e9e-9f31-9e8c28480a01";
