// FireBeetle 328P (3.3V, 8MHz). Open Serial Monitor at 9600 baud.
// Set MODE to 0 for SoftPot (3-wire + 10k pulldown), 1 for Flex (2-wire + 10k to GND).
#define MODE 0  // 0=SoftPot, 1=Flex

const int PIN = A0;
const float VCC = 3.30;        // FireBeetle 328P uses 3.3V
const int N_SAMPLES = 10;      // simple averaging
const int TOUCH_THRESH = 40;   // SoftPot: raw > this == touched (tune if needed)
const float R_FIXED = 10000.0; // Flex mode: the fixed resistor value (10k)

int analogSmooth() {
  long sum = 0;
  for (int i = 0; i < N_SAMPLES; i++) {
    sum += analogRead(PIN);
    delay(2);
  }
  return (int)(sum / N_SAMPLES);
}

void setup() {
  Serial.begin(115200); // 9600 recommended at 8 MHz
  // No pinMode needed for analog input
  delay(300);
  Serial.println(F("Ready."));
  if (MODE == 0) Serial.println(F("Mode: SoftPot (3-wire)"));
  else           Serial.println(F("Mode: Flex (2-wire divider)"));
}

void loop() {
  int raw = analogSmooth();
  float volts = (raw * VCC) / 1023.0;

  if (MODE == 0) {
    // --- SoftPot readout ---
    // If using 10k pulldown: ~0 when untouched; rises with finger position.
    bool touched = raw > TOUCH_THRESH;
    float positionPct = touched ? (100.0f * raw / 1023.0f) : 0.0f;

    Serial.print(F("raw=")); Serial.print(raw);
    Serial.print(F("  V=")); Serial.print(volts, 3);
    Serial.print(F("  touched=")); Serial.print(touched ? F("YES") : F("no "));
    Serial.print(F("  pos%=")); Serial.println(positionPct, 1);

  } else {
    // --- Flex sensor readout ---
    // Divider: Vout = VCC * (R_fixed / (R_flex + R_fixed)) if flex is at VCC side.
    // Solve for R_flex:
    //   R_flex = R_fixed * (VCC / Vout - 1)
    float rFlex = (volts > 0.01f) ? (R_FIXED * (VCC / volts - 1.0f)) : 1e9;
    Serial.print(F("raw=")); Serial.print(raw);
    Serial.print(F("  V=")); Serial.print(volts, 3);
    Serial.print(F("  Rflex~=")); Serial.print(rFlex, 0);
    Serial.println(F(" ohms"));
  }

  delay(50);
}
