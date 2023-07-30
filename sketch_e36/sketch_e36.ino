#include <SoftwareSerial.h>
#include <String.h>
#include <EEPROM.h>
#include <AltSoftSerial.h>
#include <Adafruit_Fingerprint.h>


SoftwareSerial EEBlue(11, 10);  // TX | RX
SoftwareSerial fingerprintSerial(4, 3);

Adafruit_Fingerprint finger = Adafruit_Fingerprint(&fingerprintSerial);

const int relayPin = 6;          // pino do rele
const int buttonPin = A0;        // Switch liga/desliga
const int switchPinBLE = A1;     // Module Bluetooth
const int switchPinFinger = A2;  // Module Fingerprint

unsigned long startTime;
bool minhaVariavel = true;
unsigned long tresMinutos = 180000;

int valorLido;
bool botaoPressionado = false;

//Variaveis do sistema
bool adminMode = false;
bool hasAdmin = false;
bool lockState = true;
bool inOficinaMode;
bool inGarageMode;
bool inLockdownMode;  // prendeu o carro? blz, só leva no guincho :)
int countStartWithoutPwd = 0;
int maxStartAtOficinaMode = -1;
int maxStartAtGarageMode = 15;
bool connectionValidated = false;
String verifyCode = "drift";
String verifyCode2 = "lock";
//Fim variaveis do sistema

//Funções do SO
uint8_t modoGravacaoID(uint8_t IDgravar, bool isAdmin = false);
//Fim funções do SO

void recoveryData() {
  byte adminId = EEPROM.read(1);
  hasAdmin = (adminId != 0xFF);
  inOficinaMode = EEPROM.read(5);
  inGarageMode = EEPROM.read(6);
  inLockdownMode = EEPROM.read(7);
  countStartWithoutPwd = EEPROM.read(8);
}

void setup() {
  pinMode(buttonPin, INPUT);  // Configura o pino do botão como entrada
  pinMode(switchPinBLE, OUTPUT);
  pinMode(switchPinFinger, OUTPUT);
  digitalWrite(switchPinBLE, LOW);
  digitalWrite(switchPinFinger, HIGH);
  Serial.begin(9600);
  // EEBlue.begin(9600);  //Baud Rate for command Mode.
  finger.begin(57600);
  fingerprintSerial.begin(57600);
  startTime = millis(); 
  pinMode(relayPin, OUTPUT);

  if (inOficinaMode) {
    digitalWrite(relayPin, LOW);
    digitalWrite(switchPinFinger, LOW);
  } else if (inGarageMode) {
    if (countStartWithoutPwd <= maxStartAtGarageMode) {
      digitalWrite(relayPin, LOW);
      if (inGarageMode) {
        int netTick = countStartWithoutPwd + 1;
        EEPROM.write(8, netTick);
      }
    }
  } else {
    digitalWrite(relayPin, HIGH);
  }

  recoveryData();

  Serial.println("Started System!");
}

void sendAppData() {
  // Montar a mensagem com os dados separados por "|"
  Serial.print("ndcr:verify2:");
  Serial.print(lockState);
  Serial.print("|");
  Serial.print(adminMode);
  Serial.print("|");
  Serial.print(hasAdmin);
  Serial.print("|");
  Serial.print(inOficinaMode);
  Serial.print("|");
  Serial.print(inGarageMode);
  Serial.print("|");
  Serial.print(inLockdownMode);
  Serial.print("|");
  Serial.print(countStartWithoutPwd);
  Serial.print("|");
  Serial.print(maxStartAtGarageMode);
  Serial.print("|");
  Serial.print(maxStartAtParkingMode);
  Serial.println("#");
}

void setMode(String mode, bool state) {
  if (mode == "oficina") {
    inOficinaMode = state;
    inGarageMode = false;
  } else if (mode == "garage") {
    if (inGarageMode && !state) {
      int netTick = 0;
      EEPROM.write(8, netTick);
    }
    inGarageMode = state;
    inOficinaMode = false;
  } else if (mode == "lockdown") {
    inLockdownMode = state;
    inOficinaMode = false;
    inGarageMode = false;
  }

  EEPROM.write(5, inOficinaMode);
  EEPROM.write(6, inGarageMode);
  EEPROM.write(7, inLockdownMode);
}

void processCommand(String command) {
  if (command.startsWith("ndc:")) {
    String data = command.substring(4); // Remove o "ndc:" do início da string
    // Verifica se é um comando apenas com chave ou com chave e valor
    if (data.indexOf(':') != -1) {
      String key = data.substring(0, data.indexOf(':'));
      String value = data.substring(data.indexOf(':') + 1);
      Serial.println("Recivied => " + key + " / " + value);
      if (key == "verify") {
        if (verifyCode == value) { 
          connectionValidated = true;
          sendAppData();
        } else if (verifyCode2 == value && inLockdownMode) {
          setMode("lockdown", false);
          connectionValidated = true;
          sendAppData();
        } else {
          connectionValidated = false;
          Serial.write("ndcr:verify1#");
        }
      } else if (key == "mode") {
        if (value == "oficina") {
          setMode(value, !inOficinaMode);
        } else if (value == "garage") {
          setMode(value, !inGarageMode);
        } else if (value == "lockdown") {
          setMode(value, !inLockdownMode);
        }
      } else {
        // Comando desconhecido ou não tratado
      }
    } else {
      // Comando apenas com chave
      if (data == "lock") {
        lockState = true;
        Serial.write("ndcr:lockstate1#");
      } else if (data == "unlock") {
        lockState = false;
        Serial.write("ndcr:lockstate2#");
      } else {
        // Comando desconhecido ou não tratado
      }
    }
  }
}

void loop() {

  // Ligar o módulo de fingerprint quando o botão for pressionado
  valorLido = analogRead(buttonPin);
  if (valorLido < 500) {
    if (!botaoPressionado) {
      botaoPressionado = true;
      digitalWrite(switchPinBLE, LOW);
      digitalWrite(switchPinFinger, HIGH); // Ligar o módulo de fingerprint
    }
  } else {
    botaoPressionado = false;
    if (minhaVariavel) {
      digitalWrite(switchPinFinger, inOficinaMode ? LOW : HIGH);
    } else {
      digitalWrite(switchPinFinger, LOW);
    }
  }

  // Verifica se já passaram 3 minutos desde o início
  if (millis() - startTime >= tresMinutos) {
    minhaVariavel = false; // Define a variável como false após 3 minutos
  }

  getFingerprintIDez();

  if (Serial.available()) {
    String dataReceived = Serial.readString();
    processCommand(dataReceived);
  }
  
  adminController();

  if (lockState) {
    digitalWrite(relayPin, HIGH);
  } else {
    if (!inLockdownMode) {
      digitalWrite(relayPin, LOW);
    }
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

  lockState = !lockState;


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