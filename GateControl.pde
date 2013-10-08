// Do not remove the include below
#include "GateControl.h"

/* Opens Gate
* Pin 7 goes to the limit switch with a Brown,Black,Orange resistor (10K)
* Pin 2 goes to the transistor to open the relay
* Info on wiring up relay http://www.oomlout.com/oom.php/products/ardx/circ-11
* Use pin 16 on diagram to reverse relay
* NTP code adapted from Ardunio NTP example
*/

//Imports
#include <Time.h>
#include <SPI.h>
#include <Ethernet.h>
#include <EthernetUdp.h>
#include <TimeAlarms.h>

//Definitions for time
#define TIME_MSG_LEN  11   //Time sync to PC is HEADER followed by unix time_t as ten ascii digits
#define TIME_HEADER  'T'   //Header tag for serial time sync message
#define TIME_REQUEST  7 // ASCII bell character requests a time sync message

//Sets up Ethernet instance variables
byte mac[] = {0x90, 0xA2, 0xDA, 0x00, 0x80, 0xE7};
byte ip[] = {192, 168, 1, 60};
byte subnet[] = {255, 255, 255, 0};
byte gateway[] = {192, 168, 1, 254 };

//Ip info for NTP
unsigned int localPort = 8888;
IPAddress timeServer(193, 79, 237, 14);
const int NTP_PACKET_SIZE= 48;
byte packetBuffer[ NTP_PACKET_SIZE];
EthernetUDP Udp;
unsigned long epoch = 0;

//Default port for web server
EthernetServer server(65231);

//Relay output
unsigned int relayPin = 2;

//Reads URL from client
String readString = String(30);

//Prints clock
String printDigitString = "";

//Instance variable to see if scheduler is on
int schedulerSetting = 1;

//Tells if open or closed
int sensorValue = 0;

//Used for printing messages
String SensorString = "";


void setup()  {
  //Starts all devices
  Serial.begin(9600);
  //Initializes Ethernet shield
  Ethernet.begin(mac,ip,subnet,gateway);
  server.begin();
  Udp.begin(localPort);
  Serial.println("Syncing");
  setSyncProvider( requestSync);  //Set function to call when sync required
  Serial.println("Setting Time");
  pinMode(relayPin, OUTPUT);
  pinMode(7, INPUT);
  //Set up two alarms one at 11:00pm and one at 5:00am to open and close gate
  //Automatically
  Alarm.alarmRepeat(23,0,0, CloseNightly);
  Alarm.alarmRepeat(5,0,0, OpenDaily);
}


void loop(){
   //Adds delay in loop so alarm can fire
  Alarm.delay(1000);

  //Sets time if not set
  if(timeStatus() != timeNotSet){
    digitalWrite(13,timeStatus() == timeSet); // on if synced, off if needs refresh
  }

  delay(1000);

  //Create a client connection
  EthernetClient client = server.available();
  if (client) {
    Serial.println("Got Client");
    digitalClockDisplay();
    Serial.println("String:");
    while (client.connected()) {
      if (client.available()) {
        char c = client.read();
        //Read char by char HTTP request
        if (readString.length() < 100)
        {
          //Store characters to string
          readString += c; //replaces readString.append(c);
        }
        //Output chars to serial port
        Serial.print(c);
        //If HTTP request has ended
        if (c == '\n') {
          //Opens the gate
          sensorValue = digitalRead(7);
          if(readString.indexOf("?LED=nelson123&LED=Toggle") >0){
            digitalWrite(relayPin, HIGH);
            client.println("HTTP/1.1 200 OK");
            client.println("Content-Type: text/html");
            client.println();
            if (sensorValue == 0) {
              //If gate is already closed then opens
              SensorString = "Gate is Opening";
            }
            else {
              //If gate is already open then closes it
              SensorString = "Gate is Closing";
            }
            client.print("<script type='text/javascript'>alert(\"");
            client.print(SensorString);
            client.print("\");  location = \"http://192.168.1.60:65231/\"; </script>");
          }

         //Gets status of the device, open or closed, scheduler on or off
          if(readString.indexOf("?LED=nelson123&LED=Status") >0){
             client.println("HTTP/1.1 200 OK");
             client.println("Content-type: text/html");
             client.println();
            if (sensorValue == 0) {
               if (schedulerSetting == 1) {
                 SensorString = "Gate Open and Scheduler On";
               }
               else {
                 SensorString = "Gate Open and Scheduler Off";
               }
           }
           else {
               if (schedulerSetting == 1) {
                 SensorString = "Gate Closed and Scheduler On";
               }
               else {
                 SensorString = "Gate Closed and Scheduler Off";
               }
             }
             client.print("<script type='text/javascript'>alert(\"");
             client.print(SensorString);
             client.println("\");  location = \"http://192.168.1.60:65231/\"; </script>");
        }
         //Turns scheduler on or off
         if(readString.indexOf("?LED=nelson123&LED=ChangeScheduler") > 0) {
           if (schedulerSetting == 0) {
             schedulerSetting = 1;
             client.println("HTTP/1.1 200 OK");
             client.println("Content-Type: text/html");
             client.println();
             client.println("<script type='text/javascript'>alert(\"Scheduler On\");  location = \"http://192.168.1.60:65231/\"; </script>");
           }
           else {
             schedulerSetting = 0;
             client.println("HTTP/1.1 200 OK");
             client.println("Content-Type: text/html");
             client.println();
             client.println("<script type='text/javascript'>alert(\"Scheduler Off\");  location = \"http://192.168.1.60:65231/\"; </script>");
           }
          }

          // Homepage
          client.println("HTTP/1.1 200 OK");
          client.println("Content-Type: text/html");
          client.println();
          client.println("<html><head><title>Control</title></head>");
          client.println("<body><center>");
          client.println("Time is:");
          client.print(hour());
          client.print(printDigits(minute()));
          client.print(printDigits(second()));
          client.print(" ");
          client.print(month());
          client.print("/");
          client.print(day());
          client.print("/");
          client.print(year());
          client.println("<form>Password: <input type=password name=LED />");
          client.println("<br /> <input name=LED type=submit value=Toggle>");
          client.println("<input name=LED type=submit value=ChangeScheduler>");
          client.print("<input name=LED type=submit value=Status ></form>");
          client.println("</center></body></html>");
          //Clearing string for next read
          readString="";
          //Stopping client
          client.stop();
          Serial.println("Client Disconnected");
          Serial.println(" ");
          //Wait for relay, then change state to closed
          delay(500);
          digitalWrite(relayPin, LOW);
        }
      }
    }
  }
}


//Scheduler for closing nightly
void CloseNightly(){
  int sensorread = digitalRead(7);
  if(sensorread == 0 && schedulerSetting == 1){
    digitalWrite(relayPin, HIGH);
    delay(500);
    digitalWrite(relayPin, LOW);
    Serial.print("close done");
    digitalClockDisplay();
   }
  else{
    Serial.print("close skip");
    digitalClockDisplay();
  }

}

//Scheduler for opening in the morning
void OpenDaily(){
  int sensorread = digitalRead(7);
  if(sensorread == 0 && schedulerSetting == 1){
    digitalWrite(relayPin, HIGH);
    delay(500);
    digitalWrite(relayPin, LOW);
    Serial.print("open done");
    digitalClockDisplay();
  }
  else{
    Serial.print("open skip");
    digitalClockDisplay();
  }

}

//Used to display the time to serial
void digitalClockDisplay(){
  Serial.print(hour());
  Serial.print(printDigits(minute()));
  Serial.print(printDigits(second()));
  Serial.print(" ");
  Serial.print(day());
  Serial.print(" ");
  Serial.print(month());
  Serial.print(" ");
  Serial.print(year());
  Serial.println();
}


//Used to save the time to a string for printing to webpage
String printDigits(int digits){
  printDigitString = "";
  printDigitString = printDigitString + ":";
  if(digits < 10){
    printDigitString = printDigitString + "0";
  }
  printDigitString = printDigitString + digits;
  return printDigitString;
}


//Request synce with NTP
time_t requestSync(){
  Serial.println("Requested Sync");
  sendNTPpacket(timeServer); // send an NTP packet to a time server
  Serial.println("Talking to NTP");
  delay(1000);
  if ( Udp.parsePacket() ) {
    // We've received a packet, read the data from it
    Udp.read(packetBuffer,NTP_PACKET_SIZE);  // read the packet into the buffer

    //the timestamp starts at byte 40 of the received packet and is four bytes,
    // or two words, long. First, esxtract the two words:

    unsigned long highWord = word(packetBuffer[40], packetBuffer[41]);
    unsigned long lowWord = word(packetBuffer[42], packetBuffer[43]);
    // combine the four bytes (two words) into a long integer
    // this is NTP time (seconds since Jan 1 1900):
    unsigned long secsSince1900 = highWord << 16 | lowWord;
    const unsigned long seventyYears = 2208988800UL;
    const unsigned long TimeZone = 28800L;
    // subtract seventy years:
    unsigned long epoch = secsSince1900 - seventyYears;
    epoch = epoch - TimeZone;
    // print Unix time:
    return epoch;
  }
}

//Communication with NTP
unsigned long sendNTPpacket(IPAddress& address)
{
  // set all bytes in the buffer to 0
  memset(packetBuffer, 0, NTP_PACKET_SIZE);
  // Initialize values needed to form NTP request
  // (see URL above for details on the packets)
  packetBuffer[0] = 0b11100011;   // LI, Version, Mode
  packetBuffer[1] = 0;     // Stratum, or type of clock
  packetBuffer[2] = 6;     // Polling Interval
  packetBuffer[3] = 0xEC;  // Peer Clock Precision
  // 8 bytes of zero for Root Delay & Root Dispersion
  packetBuffer[12]  = 49;
  packetBuffer[13]  = 0x4E;
  packetBuffer[14]  = 49;
  packetBuffer[15]  = 52;

  // all NTP fields have been given values, now
  // you can send a packet requesting a timestamp:
  Udp.beginPacket(address, 123); //NTP requests are to port 123
  Udp.write(packetBuffer,NTP_PACKET_SIZE);
  Udp.endPacket();
}
