#include "ble_link.h"
#include "config.h"
#include "display.h"
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <atomic>
#include <cstdlib>

// Les callbacks BLE ne modifient jamais l'affichage : transfert vers loop().
struct Command { char line[96]; uint32_t generation; };
static QueueHandle_t inbox;
static BLECharacteristic* response;
static std::atomic<bool> restartAdvertising{false};
static std::atomic<bool> connected{false};
static std::atomic<uint32_t> generation{0};

class Receiver : public BLECharacteristicCallbacks {
  char buffer[96]{};
  size_t used=0;
  bool discard=false;
  uint32_t lastByte=0, lastGeneration=0;
  void onWrite(BLECharacteristic* characteristic) override {
    const auto session=generation.load();
    if(session!=lastGeneration || millis()-lastByte>3000) { used=0;discard=false; }
    lastGeneration=session;
    lastByte=millis();
    const std::string bytes=characteristic->getValue();
    for(const unsigned char ch : bytes) {
      if(ch=='\n') {
        if(!discard && used>0) {
          Command command{};
          memcpy(command.line,buffer,used);
          command.generation=session;
          // Si la queue est pleine, pas d'ACK : l'application signalera un timeout.
          if(xQueueSend(inbox,&command,0)!=pdTRUE) Serial.println("BLE : queue pleine");
        }
        used=0; discard=false;
      } else if(ch<32 || ch>126 || used>=sizeof(buffer)-1) {
        discard=true;
      } else if(!discard) buffer[used++]=ch;
    }
  }
};

class ServerEvents : public BLEServerCallbacks {
  void onConnect(BLEServer*) override {
    generation.fetch_add(1);connected=true;Serial.println("BLE : connecté");
  }
  void onDisconnect(BLEServer*) override {
    connected=false;generation.fetch_add(1);restartAdvertising=true;
    Serial.println("BLE : déconnecté, reprise de la publicité");
  }
};

void bleBegin() {
  inbox=xQueueCreate(6,sizeof(Command));
  if(!inbox) { Serial.println("Erreur mémoire BLE"); return; }
#if LUMA_PANEL_COLOR
  BLEDevice::init("Luma couleur");
#else
  BLEDevice::init("Luma rouge");
#endif
  auto server=BLEDevice::createServer();
  server->setCallbacks(new ServerEvents());
  auto service=server->createService(SERVICE_UUID);
  auto input=service->createCharacteristic(WRITE_UUID,BLECharacteristic::PROPERTY_WRITE);
  input->setCallbacks(new Receiver());
  response=service->createCharacteristic(NOTIFY_UUID,BLECharacteristic::PROPERTY_NOTIFY);
  response->addDescriptor(new BLE2902());
  service->start();
  auto advertising=BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->start();
}

void bleTick() {
  if(!inbox) return;
  if(restartAdvertising.exchange(false)) BLEDevice::startAdvertising();
  Command command{};
  if(xQueueReceive(inbox,&command,0)!=pdTRUE) return;
  if(!connected || command.generation!=generation.load()) return;
  auto line=command.line;
  if(line[0]=='\0' || line[1]!=':' || line[2]<'0' || line[2]>'9') return;
  char* end;
  long id=strtol(line+2,&end,10);
  if(id<1 || id>65535 || (*end!=':' && *end!='\0')) return;
  const char* payload=*end==':' ? end+1 : end;
  const bool ok=applyCommand(line[0],payload);
  char ack[32];
  snprintf(ack,sizeof(ack),ok ? "OK:%ld\n" : "ERR:%ld:INVALID\n",id);
  if(connected && command.generation==generation.load()) {
    response->setValue(reinterpret_cast<uint8_t*>(ack),strlen(ack));
    response->notify();
  }
  Serial.printf("Commande %c #%ld : %s\n",line[0],id,ok ? "OK" : "refusée");
}
