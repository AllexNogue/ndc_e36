#include <SoftwareSerial.h>
#include <EEPROM.h>
#include <Adafruit_Fingerprint.h>

SoftwareSerial mySerial(4, 3);
Adafruit_Fingerprint finger = Adafruit_Fingerprint(&mySerial);

SoftwareSerial EEBlue(11, 10);  // TX | RX
const int relayPin = 6;         // pino do rele

//Variaveis do sistema
bool adminMode = false;
bool hasAdmin = false;
bool lockState = false;
bool inParkingMode = false;
bool inGarageMode = false;
bool lockedForPolice = false;  // prendeu o carro? blz, só leva no guincho :)
int countStartWithoutPwd = 0;
int maxStartAtGarageMode = -1;
int maxStartAtParkingMode = 15;
//Fim variaveis do sistema

//Funções do SO
uint8_t modoGravacaoID(uint8_t IDgravar, bool isAdmin = false);
//Fim funções do SO

void recoveryData() {
  byte adminId = EEPROM.read(1);
  hasAdmin = (adminId != 0xFF);
  inParkingMode = EEPROM.read(5);
  inGarageMode = EEPROM.read(6);
  lockedForPolice = EEPROM.read(7);
  countStartWithoutPwd = EEPROM.read(8);
}

void setup() {
  Serial.begin(9600);
  EEBlue.begin(9600);  //Baud Rate for command Mode.
  finger.begin(57600);

  pinMode(relayPin, OUTPUT);
  // Inicialmente, desligar o relé
  digitalWrite(relayPin, HIGH);

  if (finger.verifyPassword()) {
    Serial.println("Leitor FPM10A encontrado!");
  } else {
    Serial.println("Leitor FPM10A não encontrado. Verifique as conexões.");
    while (1)
      ;  // Se o leitor não for encontrado, pare o programa
  }

  recoveryData();

  Serial.println("Started System!");
}

void loop() {
  adminController();
  getFingerprintIDez();
  // Keep reading from HC-05 and send to Arduino Serial Monitor
  if (EEBlue.available()) {
    char data = EEBlue.read();
    Serial.println(data);

    if (data == 'a') {
      // Se o dado recebido for "a", definir a variável adminMode como verdadeira (true)
      adminMode = true;
      Serial.println("adminMode ativado!");  // Opcional: enviar um feedback para o aplicativo
    }

    if (data == 'c') {
      // Se o dado recebido for "c", ativar o relé
      digitalWrite(relayPin, LOW);
      // Aguardar um curto período para acionar o relé (ajuste conforme necessário)
      delay(1500);
      // Desligar o relé após um curto período (ajuste conforme necessário)
      digitalWrite(relayPin, HIGH);
    }
  }

  // Keep reading from Arduino Serial Monitor and send to HC-05
  if (Serial.available()) {
    char data = Serial.read();
    EEBlue.write(data);
  }
}


int getFingerprintIDez() {
  uint8_t p = finger.getImage();
  if (p != FINGERPRINT_OK) return -1;

  p = finger.image2Tz();
  if (p != FINGERPRINT_OK) return -1;

  p = finger.fingerFastSearch();
  if (p != FINGERPRINT_OK) {
    Serial.println("Digital invalida.");
    return -1;
  }

  //Encontrou uma digital!
  if (finger.fingerID == hasAdmin) {
    Serial.print("Modo Administrador!");
    adminMode = !adminMode;
  }

  if (lockState) {
    lockState = false;
    digitalWrite(relayPin, HIGH);
  } else {
    lockState = true;
    digitalWrite(relayPin, LOW);
  }
  
  Serial.print("ID encontrado #");
  Serial.print(finger.fingerID);
  Serial.print(" com confiança de ");
  Serial.println(finger.confidence);
  return finger.fingerID;
}


uint8_t modoGravacaoID(uint8_t IDgravar, bool isAdmin = false) {

  int p = -1;
  Serial.print("Esperando uma leitura válida para gravar #");
  Serial.println(IDgravar);
  delay(2000);
  while (p != FINGERPRINT_OK) {
    p = finger.getImage();
    switch (p) {
      case FINGERPRINT_OK:
        Serial.println("Leitura concluída");
        break;
      case FINGERPRINT_NOFINGER:
        Serial.println(".");
        delay(200);
        break;
      case FINGERPRINT_PACKETRECIEVEERR:
        Serial.println("Erro comunicação");
        break;
      case FINGERPRINT_IMAGEFAIL:
        Serial.println("Erro de leitura");
        break;
      default:
        Serial.println("Erro desconhecido");
        break;
    }
  }

  // OK successo!

  p = finger.image2Tz(1);
  switch (p) {
    case FINGERPRINT_OK:
      Serial.println("Leitura convertida");
      break;
    case FINGERPRINT_IMAGEMESS:
      Serial.println("Leitura suja");
      return p;
    case FINGERPRINT_PACKETRECIEVEERR:
      Serial.println("Erro de comunicação");
      return p;
    case FINGERPRINT_FEATUREFAIL:
      Serial.println("Não foi possível encontrar propriedade da digital");
      return p;
    case FINGERPRINT_INVALIDIMAGE:
      Serial.println("Não foi possível encontrar propriedade da digital");
      return p;
    default:
      Serial.println("Erro desconhecido");
      return p;
  }

  Serial.println("Remova o dedo");
  delay(2000);
  p = 0;
  while (p != FINGERPRINT_NOFINGER) {
    p = finger.getImage();
  }
  Serial.print("ID ");
  Serial.println(IDgravar);
  p = -1;
  Serial.println("Coloque o Mesmo dedo novamente");
  while (p != FINGERPRINT_OK) {
    p = finger.getImage();
    switch (p) {
      case FINGERPRINT_OK:
        Serial.println("Leitura concluída");
        break;
      case FINGERPRINT_NOFINGER:
        Serial.print(".");
        delay(200);
        break;
      case FINGERPRINT_PACKETRECIEVEERR:
        Serial.println("Erro de comunicação");
        break;
      case FINGERPRINT_IMAGEFAIL:
        Serial.println("Erro de Leitura");
        break;
      default:
        Serial.println("Erro desconhecido");
        break;
    }
  }

  // OK successo!

  p = finger.image2Tz(2);
  switch (p) {
    case FINGERPRINT_OK:
      Serial.println("Leitura convertida");
      break;
    case FINGERPRINT_IMAGEMESS:
      Serial.println("Leitura suja");
      return p;
    case FINGERPRINT_PACKETRECIEVEERR:
      Serial.println("Erro de comunicação");
      return p;
    case FINGERPRINT_FEATUREFAIL:
      Serial.println("Não foi possível encontrar as propriedades da digital");
      return p;
    case FINGERPRINT_INVALIDIMAGE:
      Serial.println("Não foi possível encontrar as propriedades da digital");
      return p;
    default:
      Serial.println("Erro desconhecido");
      return p;
  }

  // OK convertido!
  Serial.print("Criando modelo para #");
  Serial.println(IDgravar);

  p = finger.createModel();
  if (p == FINGERPRINT_OK) {
    Serial.println("As digitais batem!");
  } else if (p == FINGERPRINT_PACKETRECIEVEERR) {
    Serial.println("Erro de comunicação");
    return p;
  } else if (p == FINGERPRINT_ENROLLMISMATCH) {
    Serial.println("As digitais não batem");
    return p;
  } else {
    Serial.println("Erro desconhecido");
    return p;
  }

  Serial.print("ID ");
  Serial.println(IDgravar);
  p = finger.storeModel(IDgravar);
  if (p == FINGERPRINT_OK) {
    if (isAdmin && IDgravar < 5) {
      EEPROM.write(IDgravar, IDgravar);  // Salva na memoria o id da digital do administrador
    }
    Serial.println("Armazenado!");
  } else if (p == FINGERPRINT_PACKETRECIEVEERR) {
    Serial.println("Erro de comunicação");
    return p;
  } else if (p == FINGERPRINT_BADLOCATION) {
    Serial.println("Não foi possível gravar neste local da memória");
    return p;
  } else if (p == FINGERPRINT_FLASHERR) {
    Serial.println("Erro durante escrita na memória flash");
    return p;
  } else {
    Serial.println("Erro desconhecido");
    return p;
  }
}



// SO
void adminController() {
  if (!hasAdmin) {
    modoGravacaoID(1, true);  // se não tiver um admin iremos forçar a gravação de um
    hasAdmin = true;
  }
}