#!/bin/bash
# Створює стабільний самопідписаний сертифікат для code signing,
# щоб TCC (Accessibility) памʼятав дозвіл і не перепитував щоразу.
# Запускати ОДИН раз. Потрібен пароль адміністратора (для довіри до сертифіката).
set -e

CERT_NAME="ClipHistory Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
TMP="$(mktemp -d)"

# Вже існує?
if security find-certificate -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "✅ Сертифікат «$CERT_NAME» вже існує — нічого робити."
    exit 0
fi

echo "→ Генерую ключ + самопідписаний сертифікат…"
cat > "$TMP/ext.cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = ClipHistory Self-Signed
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -config "$TMP/ext.cnf"

# -legacy + непорожній пароль — інакше macOS `security` не читає p12 від OpenSSL 3.x
P12PASS="cliphistory"
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/cert.p12" -passout "pass:$P12PASS" -name "$CERT_NAME"

echo "→ Імпортую у login.keychain (дозволяю codesign користуватись без запиту)…"
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P "$P12PASS" \
    -T /usr/bin/codesign -T /usr/bin/security

echo "→ Роблю сертифікат довіреним для підпису коду (потрібен пароль адміна)…"
sudo security add-trusted-cert -d -r trustRoot \
    -p codeSign -k /Library/Keychains/System.keychain "$TMP/cert.pem"

rm -rf "$TMP"

echo
echo "✅ Готово. Перевір:"
security find-identity -v -p codesigning | grep "$CERT_NAME" || true
echo
echo "Тепер перезбери застосунок:  ./build-daemon.sh"
