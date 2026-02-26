# DALIHub Installer

DALI 조명 제어 시스템 설치 스크립트

## 빠른 설치

```bash
curl -sSL https://raw.githubusercontent.com/niot-inc/dalihub-installer/main/install.sh | sudo bash
```

## 요구사항

- **하드웨어**: Raspberry Pi 4/5 + DALI HAT
- **OS**: Raspberry Pi OS (64-bit 권장), Debian 11+, Ubuntu 22.04+
- **네트워크**: 인터넷 연결 (설치 시)

## 설치되는 구성요소

| 서비스 | 포트 | 설명 |
|--------|------|------|
| DALIHub | 3000 | 웹 UI 및 REST API |
| Mosquitto | 1883 | MQTT 브로커 |
| Mosquitto WS | 9001 | MQTT over WebSocket |
| Watchtower | - | 자동 업데이트 (선택) |

## 설치 옵션

```bash
# 기본 설치
sudo bash install.sh

# UART 설정 건너뛰기 (비-Pi 환경)
sudo bash install.sh --skip-uart

# 설치 경로 지정
sudo bash install.sh --install-dir /home/pi/dalihub
```

## 설치 후 접속

설치 완료 후:

- **Web UI**: `http://<라즈베리파이-IP>:3000`
- **MQTT**: `mqtt://<라즈베리파이-IP>:1883`
  - Username: `dalihub`
  - Password: `dalihub`

## 설정 파일

설치 위치: `/opt/dalihub`

```
/opt/dalihub/
├── docker-compose.yml    # Docker 구성
├── .env                  # 환경 설정
├── config/               # DALIHub 설정
├── data/                 # 데이터 저장
├── logs/                 # 로그
└── mosquitto/            # MQTT 브로커
    ├── config/
    ├── data/
    └── log/
```

### 환경 변수 (.env)

```bash
# DALIHub 버전
DALIHUB_VERSION=1.0.0

# 포트
DALIHUB_PORT=3000
MQTT_PORT=1883

# 시리얼 장치
SERIAL_DEVICE=/dev/ttyAMA0

# MQTT 인증 (변경 권장!)
MQTT_USERNAME=dalihub
MQTT_PASSWORD=dalihub

# 자동 업데이트
AUTO_UPDATE=true
UPDATE_INTERVAL=86400
```

## 자동 업데이트

Watchtower를 통해 DALIHub 컨테이너가 자동으로 업데이트됩니다.

### 비활성화

`.env` 파일에서:
```bash
AUTO_UPDATE=false
```

변경 후 재시작:
```bash
cd /opt/dalihub
docker compose down
docker compose up -d
```

### 수동 업데이트

```bash
cd /opt/dalihub
docker compose pull
docker compose up -d
```

## 관리 명령어

```bash
cd /opt/dalihub

# 상태 확인
docker compose ps

# 로그 보기
docker compose logs -f
docker compose logs -f dalihub      # DALIHub만
docker compose logs -f mosquitto    # MQTT만

# 재시작
docker compose restart

# 중지
docker compose down

# 시작
docker compose up -d
```

## 제거

```bash
curl -sSL https://raw.githubusercontent.com/niot-inc/dalihub-installer/main/uninstall.sh | sudo bash
```

또는:
```bash
sudo bash /opt/dalihub/uninstall.sh
```

## 문제 해결

### 시리얼 포트 연결 안됨

1. UART 설정 확인:
   ```bash
   ls -la /dev/ttyAMA0
   ```

2. 재부팅 필요할 수 있음:
   ```bash
   sudo reboot
   ```

### MQTT 연결 실패

1. Mosquitto 상태 확인:
   ```bash
   docker compose logs mosquitto
   ```

2. 인증 정보 확인 (`.env` 파일)

### 컨테이너 시작 안됨

1. Docker 상태 확인:
   ```bash
   sudo systemctl status docker
   ```

2. 로그 확인:
   ```bash
   docker compose logs
   ```

## 라이선스

Commercial License - See LICENSE file

## 지원

- 이슈: [GitHub Issues](https://github.com/niot-inc/dalihub-installer/issues)
- 문서: [Documentation](https://niot-inc.github.io/dalihub-installer)
