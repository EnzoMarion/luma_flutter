#include "display.h"
#include "config.h"
#include <cstring>
#include <cstdlib>

#if LUMA_PANEL_COLOR
#include <Adafruit_NeoMatrix.h>
#include <Adafruit_NeoPixel.h>
static Adafruit_NeoMatrix colorPanel(
  RGB_WIDTH, RGB_HEIGHT, PIN_RGB,
  NEO_MATRIX_TOP + NEO_MATRIX_LEFT + NEO_MATRIX_ROWS + NEO_MATRIX_ZIGZAG,
  NEO_GRB + NEO_KHZ800);
#else
#include <MD_Parola.h>
static MD_Parola panel(HARDWARE, PIN_DIN, PIN_CLK, PIN_CS, MODULES);
#endif

static char message[61] = "MERCI";
static int intensity=6, speedMs=65, mode=0, direction=0, powerOn=1;
static int iconIndex=-1;
static bool blank=false, scrolling=false;
static uint32_t activeColor=0xD7FF7F;
static int scrollX=RGB_WIDTH;
static uint32_t lastScroll=0;
static const uint8_t icons[6][8] = {
  {0x3c,0x42,0xa5,0x81,0xa5,0x99,0x42,0x3c},
  {0x00,0x66,0xff,0xff,0x7e,0x3c,0x18,0x00},
  {0x10,0x18,0xfc,0xfe,0xfc,0x18,0x10,0x00},
  {0x24,0x18,0x7e,0xdb,0xdb,0x7e,0x18,0x24},
  {0x3c,0x42,0xa9,0x81,0xa5,0x99,0x42,0x3c},
  {0x66,0x66,0x66,0x66,0x66,0x66,0x66,0x00},
};

#if LUMA_PANEL_COLOR
static uint16_t color565(uint32_t rgb) {
  const uint8_t r=(rgb>>16)&0xff, g=(rgb>>8)&0xff, b=rgb&0xff;
  return static_cast<uint16_t>(((r&0xf8)<<8)|((g&0xfc)<<3)|(b>>3));
}

static void renderColor() {
  colorPanel.fillScreen(0);
  if(blank || !powerOn) { colorPanel.show(); return; }
  if(iconIndex>=0) {
    const auto color=color565(activeColor);
    for(int y=0;y<8;y++) for(int x=0;x<8;x++) {
      if((icons[iconIndex][y] & (1<<(7-x))) != 0)
        colorPanel.drawPixel(x,y,color);
    }
  } else {
    colorPanel.setTextWrap(false);
    colorPanel.setTextColor(color565(activeColor));
    colorPanel.setCursor(scrollX,0);
    colorPanel.print(message);
  }
  colorPanel.show();
}
#endif

static void refresh() {
#if LUMA_PANEL_COLOR
  int16_t textX,textY;
  uint16_t textWidth,textHeight;
  colorPanel.getTextBounds(message,0,0,&textX,&textY,&textWidth,&textHeight);
  scrolling=mode==2 || (mode==0 && textWidth>RGB_WIDTH);
  colorPanel.setBrightness(static_cast<uint8_t>((intensity*255)/15));
  scrollX=scrolling
    ? (direction ? -static_cast<int>(textWidth) : RGB_WIDTH)
    : (RGB_WIDTH-static_cast<int>(textWidth))/2;
  lastScroll=millis();
  renderColor();
#else
  scrolling=mode==2 || (mode==0 && strlen(message)>10);
  panel.displaySuspend(false);
  panel.displayClear();
  panel.setIntensity(intensity);
  panel.displayShutdown(!powerOn);
  if(blank) { panel.displaySuspend(true); return; }
  if(iconIndex>=0) {
    panel.displaySuspend(true);
    auto matrix=panel.getGraphicObject();
    const int start=(MODULES*8-8)/2;
    for(int y=0;y<8;y++) for(int x=0;x<8;x++) {
      // MAX72XX numérote les colonnes de droite à gauche.
      matrix->setPoint(y,start+7-x,(icons[iconIndex][y] & (1<<(7-x))) != 0);
    }
    return;
  }
  const auto effect=direction ? PA_SCROLL_RIGHT : PA_SCROLL_LEFT;
  panel.displayText(message,PA_CENTER,speedMs,300,
    scrolling ? effect : PA_PRINT,scrolling ? effect : PA_NO_EFFECT);
  panel.displayReset();
#endif
}

void displayBegin() {
#if LUMA_PANEL_COLOR
  colorPanel.begin();
  colorPanel.setTextWrap(false);
#else
  panel.begin();
#endif
  refresh();
}

void displayTick() {
#if LUMA_PANEL_COLOR
  if(blank || !powerOn || iconIndex>=0 || !scrolling) return;
  if(millis()-lastScroll < static_cast<uint32_t>(speedMs)) return;
  lastScroll=millis();
  int16_t x1,y1;
  uint16_t textWidth,textHeight;
  colorPanel.getTextBounds(message,0,0,&x1,&y1,&textWidth,&textHeight);
  scrollX += direction ? 1 : -1;
  if(direction && scrollX > RGB_WIDTH) scrollX=-static_cast<int>(textWidth);
  if(!direction && scrollX < -static_cast<int>(textWidth)) scrollX=RGB_WIDTH;
  renderColor();
#else
  if(!blank && iconIndex<0 && panel.displayAnimate() && scrolling) panel.displayReset();
#endif
}

static bool numbers(const char* s,int* values,int count) {
  for(int i=0;i<count;i++) {
    if(*s<'0' || *s>'9') return false;
    char* end;
    long value=strtol(s,&end,10);
    if(value<0 || value>1000) return false;
    values[i]=static_cast<int>(value);
    if(i==count-1) return *end=='\0';
    if(*end!=':') return false;
    s=end+1;
  }
  return false;
}

#if LUMA_PANEL_COLOR
static bool parseColor(const char* text,uint32_t& color) {
  if(strlen(text)!=6) return false;
  uint32_t value=0;
  for(int i=0;i<6;i++) {
    const char c=text[i];
    int digit;
    if(c>='0' && c<='9') digit=c-'0';
    else if(c>='A' && c<='F') digit=c-'A'+10;
    else if(c>='a' && c<='f') digit=c-'a'+10;
    else return false;
    value=(value<<4)|static_cast<uint32_t>(digit);
  }
  color=value;
  return true;
}
#endif

bool applyCommand(char kind,const char* payload) {
  if(kind=='P') return *payload=='\0';
  if(kind=='T') {
    const size_t len=strlen(payload);
    if(len==0 || len>60) return false;
    bool nonspace=false;
    for(size_t i=0;i<len;i++) {
      if(payload[i]<32 || payload[i]>126) return false;
      if(payload[i]!=' ') nonspace=true;
    }
    if(!nonspace) return false;
    memcpy(message,payload,len+1);
    iconIndex=-1; blank=false;
  } else if(kind=='I') {
    int value;
    if(!numbers(payload,&value,1) || value>5) return false;
    iconIndex=value; blank=false;
  } else if(kind=='S') {
    int v[5];
    if(!numbers(payload,v,5) || v[0]>15 || v[1]<20 || v[1]>200 ||
       v[2]>2 || v[3]>1 || v[4]>1) return false;
    intensity=v[0];speedMs=v[1];mode=v[2];direction=v[3];powerOn=v[4];
  } else if(kind=='C') {
    if(*payload!='\0') return false;
    blank=true;
  } else if(kind=='K') {
#if LUMA_PANEL_COLOR
    uint32_t color;
    if(!parseColor(payload,color)) return false;
    activeColor=color;
#else
    return false;
#endif
  } else return false;
  refresh();
  return true;
}
