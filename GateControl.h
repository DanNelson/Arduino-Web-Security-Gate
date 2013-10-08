#ifndef GateControl_H_
#define GateControl_H_
//Libraries to include
#include "Arduino.h"
#include <Time.h>
#include <SPI.h>
#include <Ethernet.h>
#include <EthernetUdp.h>
#include <TimeAlarms.h>

#ifdef __cplusplus
extern "C" {
#endif
void loop();
void setup();
#ifdef __cplusplus
}
#endif

//Function Prototypes
void CloseNightly();
void OpenDaily();
void digitalClockDisplay();
String printDigits(int digits);
time_t requestSync();
unsigned long sendNTPpacket(IPAddress& address);


#endif
