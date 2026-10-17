#define TRIG_PIN 5
#define ECHO_PIN 18

// =======================================
// PARAMETER PENGUKURAN DAN KALIBRASI
// =======================================

// Jarak aktual dari permukaan sensor ke
// pembatas ujung box saat box kosong (cm)
const float JARAK_REFERENSI_KOSONG = 20.0;

// Parameter tuning akurasi
const float SKALA_KOREKSI = 1.0700;
const float OFFSET_KOREKSI_CM = -0.0372;

// Batas deteksi mobil
const float MIN_PANJANG_TERDETEKSI = 2.0;

// Parameter sampling sensor
const int JUMLAH_SAMPEL = 5;
const int MIN_SAMPEL_VALID = 3;
const float MIN_JARAK_VALID = 2.0;
const float TOLERANSI_JARAK_CM = 2.0;

// =======================================
// FUNGSI MEMBACA JARAK ULTRASONIK
// =======================================

float bacaJarakCm() {
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);

  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);

  unsigned long duration =
      pulseIn(ECHO_PIN, HIGH, 30000UL);

  if (duration == 0) {
    return -1.0;
  }

  float distance = duration * 0.0343 / 2.0;

  return distance;
}

// =======================================
// SETUP
// =======================================

void setup() {
  Serial.begin(115200);

  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);

  digitalWrite(TRIG_PIN, LOW);

  Serial.println();
  Serial.println("================================");
  Serial.println(" PENGUKUR PANJANG MOBIL");
  Serial.println(" Mode: Kalibrasi Skala + Offset");
  Serial.println("================================");

  Serial.print("Referensi box : ");
  Serial.print(JARAK_REFERENSI_KOSONG, 2);
  Serial.println(" cm");

  Serial.print("Skala koreksi : ");
  Serial.println(SKALA_KOREKSI, 4);

  Serial.print("Offset koreksi: ");
  Serial.print(OFFSET_KOREKSI_CM, 3);
  Serial.println(" cm");

  Serial.println("================================");
}

// =======================================
// LOOP UTAMA
// =======================================

void loop() {
  float totalJarak = 0.0;
  int sampelValid = 0;

  // Mengambil beberapa sampel
  for (int i = 0; i < JUMLAH_SAMPEL; i++) {
    float distance = bacaJarakCm();

    if (distance >= MIN_JARAK_VALID &&
        distance <=
        JARAK_REFERENSI_KOSONG + TOLERANSI_JARAK_CM) {
      totalJarak += distance;
      sampelValid++;
    }

    delay(60);
  }

  // Validasi jumlah pembacaan
  if (sampelValid < MIN_SAMPEL_VALID) {
    Serial.println("Pembacaan sensor tidak valid.");
    Serial.println("------------------------------");
    delay(500);
    return;
  }

  // Rata-rata jarak sensor ke mobil
  float jarakSensor = totalJarak / sampelValid;

  // Hasil sebelum koreksi
  float panjangMentah =
      JARAK_REFERENSI_KOSONG - jarakSensor;

  Serial.print("Sampel valid       : ");
  Serial.println(sampelValid);

  Serial.print("Jarak sensor       : ");
  Serial.print(jarakSensor, 2);
  Serial.println(" cm");

  Serial.print("Panjang sebelum    : ");
  Serial.print(panjangMentah, 2);
  Serial.println(" cm");

  // Deteksi mobil menggunakan hasil mentah
  // agar offset tidak membuat box kosong
  // dianggap berisi mobil.
  if (panjangMentah < MIN_PANJANG_TERDETEKSI) {
    Serial.println(
        "Status: Mobil belum terdeteksi."
    );
    Serial.println("------------------------------");
    delay(500);
    return;
  }

  if (panjangMentah > JARAK_REFERENSI_KOSONG) {
    Serial.println(
        "Status: Hasil mentah di luar rentang box."
    );
    Serial.println("------------------------------");
    delay(500);
    return;
  }

  // =====================================
  // KOREKSI HASIL PENGUKURAN
  // =====================================

  float panjangTerkoreksi =
      (panjangMentah * SKALA_KOREKSI)
      + OFFSET_KOREKSI_CM;

  Serial.print("Skala koreksi      : ");
  Serial.println(SKALA_KOREKSI, 4);

  Serial.print("Offset koreksi     : ");
  Serial.print(OFFSET_KOREKSI_CM, 3);
  Serial.println(" cm");

  Serial.print("PANJANG MOBIL      : ");
  Serial.print(panjangTerkoreksi, 2);
  Serial.println(" cm");

  // Memeriksa kewajaran hasil setelah koreksi
  if (panjangTerkoreksi < 0.0 ||
      panjangTerkoreksi > JARAK_REFERENSI_KOSONG) {
    Serial.println(
        "PERINGATAN: Hasil koreksi di luar rentang box."
    );
  }

  Serial.println("==============================");
  delay(500);
}