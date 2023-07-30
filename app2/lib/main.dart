import 'dart:async'; // Add this import for using Future
import 'dart:convert'; // Add this import for using utf8.encode
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: BluetoothApp(),
    );
  }
}

class BluetoothApp extends StatefulWidget {
  @override
  _BluetoothAppState createState() => _BluetoothAppState();
}

class ArduinoData {
  bool lockState;
  bool adminMode;
  bool hasAdmin;
  bool inOficinaMode; // Pode ser nulo
  bool inGarageMode; // Pode ser nulo
  bool inLockdownMode;
  int countStartWithoutPwd;
  int maxStartAtGarageMode;
  int maxStartAtParkingMode;

  ArduinoData({
    required this.lockState,
    required this.adminMode,
    required this.hasAdmin,
    required this.inOficinaMode,
    required this.inGarageMode,
    required this.inLockdownMode,
    required this.countStartWithoutPwd,
    required this.maxStartAtGarageMode,
    required this.maxStartAtParkingMode,
  });

  factory ArduinoData.fromString(String data) {
    // Remover o prefixo "ndcr:verify2:" da mensagem

    // Dividir os valores de estado usando o caractere "|"
    List<String> values = data.split('|');

    // Converter os valores de estado para os tipos apropriados
    bool lockState = values.isNotEmpty ? values[0] == '1' : false;
    bool adminMode = values.length > 1 ? values[1] == '1' : false;
    bool hasAdmin = values.length > 2 ? values[2] == '1' : false;
    bool inOficinaMode = values.length > 3 ? values[3] == '1' : false;
    bool inGarageMode = values.length > 4 ? values[4] == '1' : false;
    bool inLockdownMode = values.length > 5 ? values[5] == '1' : false;
    int countStartWithoutPwd = values.length > 6 ? int.parse(values[6]) : 0;
    int maxStartAtGarageMode = values.length > 7 ? int.parse(values[7]) : 0;
    int maxStartAtParkingMode = values.length > 8 ? int.parse(values[8]) : 0;

    return ArduinoData(
      lockState: lockState,
      adminMode: adminMode,
      hasAdmin: hasAdmin,
      inOficinaMode: inOficinaMode,
      inGarageMode: inGarageMode,
      inLockdownMode: inLockdownMode,
      countStartWithoutPwd: countStartWithoutPwd,
      maxStartAtGarageMode: maxStartAtGarageMode,
      maxStartAtParkingMode: maxStartAtParkingMode,
    );
  }
}

enum MessageType {
  lockState,
  verify,
  garageMode,
  unknown,
}

TextEditingController _passwordController = TextEditingController();

class _BluetoothAppState extends State<BluetoothApp> {
  // Initializing the Bluetooth connection state to be unknown
  BluetoothState _bluetoothState = BluetoothState.UNKNOWN;
  // Initializing a global key, as it would help us in showing a SnackBar later
  final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();
  // Get the instance of the Bluetooth
  FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;
  // Track the Bluetooth connection with the remote device
  BluetoothConnection? connection;

  int? _deviceState;
  int? _lockState;
  bool? _adminMode;
  bool? _hasAdmin;
  bool _inOficinaMode = false;
  bool _inGarageMode = false;
  bool _inLockdownMode = false;
  int? _countStartWithoutPwd;
  int? _maxStartAtGarageMode;
  int? _maxStartAtParkingMode;
  String? _enteredPassword;
  String? _selectedMode;

  bool isDisconnecting = false;
  bool _connectionValidated = false;

  // To track whether the device is still connected to Bluetooth
  bool get isConnected => connection != null && connection!.isConnected;

  // Define some variables, which will be required later
  List<BluetoothDevice> _devicesList = [];
  BluetoothDevice? _device; // Initialize as null

  bool _connected = false;
  bool _verified = false;
  bool _isButtonUnavailable = false;
  bool _modoLivreExpanded = false;

  Map<String, Color> colors = {
    'onBorderColor': Colors.green,
    'offBorderColor': Colors.red,
    'neutralBorderColor': Colors.transparent,
    'onTextColor': Colors.green,
    'offTextColor': Colors.red,
    'neutralTextColor': Colors.blue,
  };

  @override
  void initState() {
    super.initState();

    // Get current state
    FlutterBluetoothSerial.instance.state.then((state) {
      setState(() {
        _bluetoothState = state!;
        _connectionValidated = false;
      });
    });

    _deviceState = 0; // neutral
    _lockState = 0;
    _modoLivreExpanded = false;
    // If the bluetooth of the device is not enabled,
    // then request permission to turn on bluetooth
    // as the app starts up
    enableBluetooth();

    // Listen for further state changes
    FlutterBluetoothSerial.instance
        .onStateChanged()
        .listen((BluetoothState state) {
      setState(() {
        _bluetoothState = state;
        if (_bluetoothState == BluetoothState.STATE_OFF) {
          _isButtonUnavailable = true;
        }
        getPairedDevices();
      });
    });
  }

  @override
  void dispose() {
    // Avoid memory leak and disconnect
    if (isConnected) {
      isDisconnecting = true;
      connection!.dispose();
      connection = null;
    }

    super.dispose();
  }

  // Request Bluetooth permission from the user
  Future<bool> enableBluetooth() async {
    // Retrieving the current Bluetooth state
    _bluetoothState = await FlutterBluetoothSerial.instance.state;

    // If the bluetooth is off, then turn it on first
    // and then retrieve the devices that are paired.
    if (_bluetoothState == BluetoothState.STATE_OFF) {
      await FlutterBluetoothSerial.instance.requestEnable();
      await getPairedDevices();
      return true;
    } else {
      await getPairedDevices();
    }
    return false;
  }

  // For retrieving and storing the paired devices
  // in a list.
  Future<void> getPairedDevices() async {
    List<BluetoothDevice> devices = [];

    // To get the list of paired devices
    try {
      devices = await _bluetooth.getBondedDevices();
    } catch (e) {
      print('Erro ao habilitar Bluetooth: ');
    }

    // It is an error to call [setState] unless [mounted] is true.
    if (!mounted) {
      return;
    }

    // Store the [devices] list in the [_devicesList] for accessing
    // the list outside this class
    setState(() {
      _devicesList = devices;
    });
  }

  // Now, its time to build the UI
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: Text("NDC Garage - My Car"),
          backgroundColor: Colors.deepOrange,
          actions: <Widget>[
            Switch(
              value: _bluetoothState.isEnabled,
              onChanged: (bool value) {
                future() async {
                  if (value) {
                    await FlutterBluetoothSerial.instance.requestEnable();
                  } else {
                    await FlutterBluetoothSerial.instance.requestDisable();
                    setState(() {
                      _connectionValidated = false;
                    });
                  }

                  await getPairedDevices();
                  _isButtonUnavailable = false;

                  if (_connected) {
                    _disconnect();
                  }
                }

                future().then((_) {
                  setState(() {});
                });
              },
            ),
          ],
        ),
        body: Container(
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: <Widget>[
              Visibility(
                visible: _isButtonUnavailable &&
                    _bluetoothState == BluetoothState.STATE_ON,
                child: LinearProgressIndicator(
                  backgroundColor: Colors.yellow,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                ),
              ),
              Stack(
                children: <Widget>[
                  Column(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              'Veiculo:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            DropdownButton(
                              items: _getDeviceItems(),
                              onChanged: (value) =>
                                  setState(() => _device = value),
                              value: _devicesList.isNotEmpty ? _device : null,
                            ),
                            ElevatedButton(
                              onPressed: _isButtonUnavailable
                                  ? null
                                  : _connected
                                      ? _disconnect
                                      : _connect,
                              child:
                                  Text(_connected ? 'Disconnect' : 'Connect'),
                            ),
                          ],
                        ),
                      ),
                      Visibility(
                        visible: _connectionValidated,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4.0),
                            ),
                            elevation: _deviceState == 0 ? 4 : 0,
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      "Trava",
                                      style: TextStyle(
                                        fontSize: 20,
                                        color: _connectionValidated == false
                                            ? colors['neutralTextColor']!
                                            : _deviceState == 1
                                                ? colors['offTextColor']!
                                                : colors['onTextColor']!,
                                      ),
                                    ),
                                  ),
                                  ElevatedButton(
                                    onPressed: (_connectionValidated)
                                        ? _toogleLockState
                                        : null,
                                    child: Text(
                                      (_lockState == 0 || _lockState == 1)
                                          ? "Liberar"
                                          : "Travar",
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Visibility(
                        visible: (_connectionValidated && !_inLockdownMode),
                        maintainState:
                            true, // Manter o estado mesmo quando oculto
                        child: ExpansionTile(
                          title: Row(
                            children: [
                              Icon(
                                _modoLivreExpanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                color: Colors.grey,
                              ),
                              SizedBox(width: 8),
                              Text("Modos"),
                            ],
                          ),
                          onExpansionChanged: (expanded) {
                            setState(() {
                              _modoLivreExpanded = expanded;
                            });
                          },
                          children: <Widget>[
                            Row(
                              mainAxisAlignment: MainAxisAlignment
                                  .center, // Centraliza os botões horizontalmente
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8.0),
                                  child: ElevatedButton(
                                    onPressed: () {
                                      setState(() {
                                        _selectedMode = _selectedMode == "oficina" ? null : "oficina";
                                        _inOficinaMode = _selectedMode == "oficina";
                                        _inGarageMode = false;
                                        _inLockdownMode = false;
                                      });
                                      _sendModeToBlueetooth();
                                    },
                                    style: ElevatedButton.styleFrom(
                                      primary: _inOficinaMode ? Colors.green : null,
                                    ),
                                    child: Text("Oficina"),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8.0),
                                  child: ElevatedButton(
                                    onPressed: () {
                                      setState(() {
                                        // Desabilitar o botão se ele já estiver habilitado
                                        _selectedMode = _selectedMode == "garage" ? null : "garage";
                                        _inOficinaMode = false;
                                        _inGarageMode = _selectedMode == "garage"; // Ativa o lockdownMode se o modo lockdown for selecionado
                                        _inLockdownMode = false;
                                      });
                                      _sendModeToBlueetooth();
                                    },
                                    style: ElevatedButton.styleFrom(
                                      primary:
                                          _inGarageMode ? Colors.green : null,
                                    ),
                                    child: Text("Garagem"),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8.0),
                                  child: ElevatedButton(
                                    onPressed: () {
                                      setState(() {
                                        _selectedMode = _selectedMode == "lockdown" ? null : "lockdown";
                                        _inOficinaMode = false;
                                        _inGarageMode = false;
                                        _inLockdownMode = _selectedMode == "lockdown"; // Ativa o lockdownMode se o modo lockdown for selecionado
                                      });
                                      _sendModeToBlueetooth();
                                    },
                                    style: ElevatedButton.styleFrom(
                                      primary:
                                          _inLockdownMode ? Colors.green : null,
                                    ),
                                    child: Text("Lockdown"),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Container(
                    color: Colors.blue,
                  ),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          "NOTE: If you cannot find the device in the list, please pair the device by going to the Bluetooth settings",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                        SizedBox(height: 15),
                        ElevatedButton(
                          child: Text("Bluetooth Settings"),
                          onPressed: () {
                            FlutterBluetoothSerial.instance.openSettings();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  // Create the List of devices to be shown in Dropdown Menu
  List<DropdownMenuItem<BluetoothDevice>> _getDeviceItems() {
    List<DropdownMenuItem<BluetoothDevice>> items = [];
    if (_devicesList.isEmpty) {
      items.add(DropdownMenuItem(
        child: Text('NONE'),
        value: null,
      ));
    } else {
      _devicesList.forEach((device) {
        items.add(DropdownMenuItem(
          child: Text(device.name ?? "NONE"),
          value: device,
        ));
      });
    }
    return items;
  }

  // Method to connect to Bluetooth
  void _connect() async {
    setState(() {
      _isButtonUnavailable = true;
    });
    if (_device == null) {
      _waitForScaffold(context, 'No device selected');
    } else {
      await _showPasswordDialog(context);
      String? enteredPassword = _enteredPassword;
      _enteredPassword = null; // Limpar a senha depois de usar

      if (enteredPassword != null) {
        // Se o usuário digitou a senha, enviar o comando de verificação com a senha fornecida

        await BluetoothConnection.toAddress(_device!.address)
            .then((_connection) {
          print('Conectado ao dispositivo $enteredPassword');
          connection = _connection;
          dataBuffer = "";
          sendCommand("verify", value: enteredPassword);
          setState(() {
            _connected = true;
          });
        }).catchError((error) {
          print('Não é possível conectar, ocorreu um erro');
          print(error);
        });
        _waitForScaffold(context, 'Dispositivo conectado');
        setState(() => _isButtonUnavailable = false);
      }
    }
  }

  // Method to disconnect Bluetooth
  void _disconnect() async {
    setState(() {
      _isButtonUnavailable = true;
      _deviceState = 0;
    });

    await connection!.close();
    _waitForScaffold(context, 'Device disconnected');
    if (!connection!.isConnected) {
      setState(() {
        _connected = false;
        _isButtonUnavailable = false;
      });
    }
  }

  // Method to send message,
  void sendCommand(String command, {String? value}) async {
    String dataToSend = "ndc:$command";
    if (value != null) {
      dataToSend += ":$value";
    }
    connection?.output.add(Uint8List.fromList(utf8.encode(dataToSend)));
    await connection!.output.allSent;
    _waitForResponse();
  }

  void _toogleLockState() async {
    if (_lockState == 0 || _lockState == 1) {
      sendCommand("unlock");
    } else {
      sendCommand("lock");
    }
  }

  // Method to send message,
  // for turning the Bluetooth device off
  void _sendModeToBlueetooth() async {
    try {
      if (_selectedMode != null) {
        sendCommand("mode", value: _selectedMode);
      }
    } catch (e, stackTrace) {
      print("Error sending mode to Bluetooth: $e");
      print(stackTrace);
    }
  }

  // Variáveis para receber e montar os dados recebidos
  String dataBuffer = ""; // Armazena os dados recebidos parcialmente
  final String expectedPrefix =
      "ndcr:"; // Prefixo esperado das mensagens completas

  // Função para processar os dados recebidos e separar as mensagens completas
  void processData(String data) {
    // Concatenar os dados recebidos no buffer
    dataBuffer += data;
    print('New buffer: $dataBuffer');

    // Enquanto houver "#" na mensagem, processar as partes individualmente
    while (dataBuffer.contains("#")) {
      // Encontrar o índice do primeiro "#"
      int endIndex = dataBuffer.indexOf("#");

      // Verificar se a mensagem até o "#" contém "ndcr:"
      if (dataBuffer.substring(0, endIndex).contains("ndcr:")) {
        // Obter a parte relevante da mensagem que vai de "ndcr:" até o "#"
        String message =
            dataBuffer.substring(dataBuffer.indexOf("ndcr:"), endIndex + 1);

        // Processar a mensagem completa
        processDataComplete(message);
      }

      // Descartar os dados processados e o caractere "#" do buffer
      dataBuffer = dataBuffer.substring(endIndex + 1);
    }
  }

  // Função para processar a mensagem completa recebida
  void processDataComplete(String message) {
    // Remover o caractere '\n' da mensagem, se estiver presente
    message = message.replaceAll("#", "");
    dataBuffer = "";

    if (message.startsWith("ndcr:lockstate")) {
      String state = message.substring("ndcr:lockstate".length);
      int lockState = int.parse(state);
      setState(() {
        _lockState = lockState;
      });
      print("LockState: $_lockState");
    } else if (message.startsWith("ndcr:verify")) {
      int responseState = message.startsWith("ndcr:verify2") ? 2 : 1;

      if (_connected && responseState == 2) {
        print("connection accepted");
        String data = message.substring("ndcr:verify2:".length);
        ArduinoData arduinoData = ArduinoData.fromString(data);
        setState(() {
          _lockState = arduinoData.lockState ? 1 : 2;
          _adminMode = arduinoData.adminMode;
          _hasAdmin = arduinoData.hasAdmin;
          _inOficinaMode = arduinoData.inOficinaMode;
          _inGarageMode = arduinoData.inGarageMode;
          _inLockdownMode = arduinoData.inLockdownMode;
          _countStartWithoutPwd = arduinoData.countStartWithoutPwd;
          _maxStartAtGarageMode = arduinoData.maxStartAtGarageMode;
          _maxStartAtParkingMode = arduinoData.maxStartAtParkingMode;
          _connectionValidated = true;
          _modoLivreExpanded =
              _inLockdownMode == null ? false : !_inLockdownMode;
        });
      } else if (_connected) {
        _disconnect();
        setState(() {
          _connectionValidated = false;
        });
      }
    } else {
      print("Mensagem desconhecida: $message");
    }
  }

  void _waitForResponse() {
    connection?.input?.listen((Uint8List data) {
      String response = utf8.decode(data).trim();
      processData(response);
    });
  }

  void _waitForScaffold(BuildContext context, String mensagem,
      {Duration duracao = const Duration(seconds: 3)}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      show(mensagem, duracao: duracao);
    });
  }

  // Method to show a Snackbar,
  // taking message as the text
  Future<void> show(String mensagem,
      {Duration duracao = const Duration(seconds: 3)}) async {
    await Future.delayed(Duration(milliseconds: 100));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        duration: duracao,
      ),
    );
  }

  Future<void> _showPasswordDialog(BuildContext context) async {
    String? enteredPassword = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Digite a senha:'),
          content: TextField(
            controller: _passwordController,
            obscureText: true, // Para esconder a senha digitada
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Cancelar'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Confirmar'),
              onPressed: () {
                Navigator.of(context).pop(_passwordController.text);
              },
            ),
          ],
        );
      },
    );

    setState(() {
      _enteredPassword = enteredPassword;
    });
  }
}
