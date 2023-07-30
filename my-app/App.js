import React, { useEffect, useState } from 'react';
import { View, Text, Button, StyleSheet } from 'react-native';
import BleManager from 'react-native-ble-plx';

export default function App() {
  const [device, setDevice] = useState(null);
  const [isConnected, setIsConnected] = useState(false);

  useEffect(() => {
    // Inicializa o gerenciador BLE
    BleManager.start({ showAlert: false });

    // Escuta os eventos de descoberta de dispositivos BLE
    BleManager.addListener('BleManagerDiscoverPeripheral', handleDiscoverPeripheral);
    BleManager.addListener('BleManagerConnectPeripheral', handleConnectPeripheral);
    BleManager.addListener('BleManagerDisconnectPeripheral', handleDisconnectPeripheral);

    // Escuta os eventos de atualização do estado do Bluetooth no dispositivo
    BleManager.addListener('BleManagerDidUpdateState', handleUpdateState);

    // Solicita permissão para usar o Bluetooth (opcional, dependendo da versão do Android)
    BleManager.enableBluetooth()
      .then(() => console.log('Bluetooth ativado'))
      .catch((error) => console.error('Erro ao ativar Bluetooth:', error));

    return () => {
      // Remove os listeners quando o componente é desmontado
      BleManager.removeListener('BleManagerDiscoverPeripheral', handleDiscoverPeripheral);
      BleManager.removeListener('BleManagerConnectPeripheral', handleConnectPeripheral);
      BleManager.removeListener('BleManagerDisconnectPeripheral', handleDisconnectPeripheral);
      BleManager.removeListener('BleManagerDidUpdateState', handleUpdateState);
    };
  }, []);

  const handleUpdateState = (state) => {
    console.log('Estado do Bluetooth:', state);
  };

  const handleDiscoverPeripheral = (peripheral) => {
    console.log('Dispositivo encontrado:', peripheral);
    // Aqui você pode verificar se o "peripheral" é o HC-05 pelo nome, UUID, ou outras informações
  };

  const handleConnectPeripheral = (peripheral) => {
    console.log('Conectado ao dispositivo:', peripheral);
    setDevice(peripheral);
    setIsConnected(true);
  };

  const handleDisconnectPeripheral = (peripheral) => {
    console.log('Desconectado do dispositivo:', peripheral);
    setIsConnected(false);
  };

  const startScan = () => {
    // Inicia a varredura por dispositivos BLE próximos
    BleManager.scan([], 5, true)
      .then(() => console.log('Varredura iniciada'))
      .catch((error) => console.error('Erro ao iniciar varredura:', error));
  };

  const connectToDevice = () => {
    // Conecta ao dispositivo especificado pelo "device"
    BleManager.connect(device.id)
      .then(() => console.log('Conectado ao dispositivo'))
      .catch((error) => console.error('Erro ao conectar ao dispositivo:', error));
  };

  const disconnectFromDevice = () => {
    // Desconecta do dispositivo atualmente conectado
    BleManager.disconnect(device.id)
      .then(() => console.log('Desconectado do dispositivo'))
      .catch((error) => console.error('Erro ao desconectar do dispositivo:', error));
  };

  return (
    <View style={styles.container}>
      {isConnected ? (
        <>
          <Text>Conectado ao dispositivo {device?.name}</Text>
          <Button title="Desconectar" onPress={disconnectFromDevice} />
        </>
      ) : (
        <>
          <Text>Nenhum dispositivo conectado</Text>
          <Button title="Iniciar Varredura" onPress={startScan} />
          <Button title="Conectar ao Dispositivo" onPress={connectToDevice} />
        </>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
});