#include <Wire.h>
#include <Adafruit_MPR121.h>

Adafruit_MPR121 cap = Adafruit_MPR121();

uint16_t lasttouched = 0;
uint16_t currtouched = 0;
bool isAbove = false;

// Flex sensor
#define PIN A0
#define N_SAMPLES 10
#define FLEX_THRESH 40

int analogSmooth() {
  long sum = 0;
  for (int i = 0; i < N_SAMPLES; i++) {
    sum += analogRead(PIN);
    delay(1);
  }
  return sum / N_SAMPLES;
}

void setup() {
  Serial.begin(115200);
  Wire.begin();

  if (!cap.begin(0x5A)) {
    Serial.println("MPR121 not found");
    while (1);
  }
  cap.setAutoconfig(true);
}

void loop() {
  // --- MPR121 touch ---
  currtouched = cap.touched();
  for (uint8_t i = 0; i < 12; i++) {
    if ((currtouched & (1 << i)) && !(lasttouched & (1 << i))) {
      Serial.print(i); Serial.println("P"); // Press
    }
    if (!(currtouched & (1 << i)) && (lasttouched & (1 << i))) {
      Serial.print(i); Serial.println("R"); // Release
    }
  }
  lasttouched = currtouched;

  // --- Flex sensor raw value ---
  int raw = analogSmooth();
  if (raw > FLEX_THRESH) {
    if(isAbove == false){
      Serial.println("F");
    }
    isAbove = true;
  } else {
    isAbove = false;
  }

  delay(100); // ~10 Hz
}
