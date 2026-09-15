<?php

declare(strict_types=1);

// Polyfills for PHP 8.0 string functions, since this endpoint has been
// deployed on hosts running an older PHP. Behaviourally identical to the
// built-ins; only defined if the host doesn't already provide them.
if (!function_exists('str_contains')) {
    function str_contains(string $haystack, string $needle): bool
    {
        return $needle === '' || strpos($haystack, $needle) !== false;
    }
}
if (!function_exists('str_starts_with')) {
    function str_starts_with(string $haystack, string $needle): bool
    {
        return $needle === '' || strncmp($haystack, $needle, strlen($needle)) === 0;
    }
}
if (!function_exists('str_ends_with')) {
    function str_ends_with(string $haystack, string $needle): bool
    {
        return $needle === '' || substr($haystack, -strlen($needle)) === $needle;
    }
}

require_once __DIR__ . '/lib/XmlApiSimulator.php';

const MAX_BODY_BYTES = 512000;

function headerValue(string $name): ?string
{
    $serverKey = 'HTTP_' . strtoupper(str_replace('-', '_', $name));
    if (isset($_SERVER[$serverKey]) && is_string($_SERVER[$serverKey])) {
        return $_SERVER[$serverKey];
    }
    if ($name === 'Authorization' && isset($_SERVER['REDIRECT_HTTP_AUTHORIZATION'])) {
        return (string) $_SERVER['REDIRECT_HTTP_AUTHORIZATION'];
    }
    return null;
}

function xmlEscape(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES | ENT_XML1, 'UTF-8');
}

function xmlUnescape(string $value): string
{
    return html_entity_decode($value, ENT_QUOTES | ENT_XML1, 'UTF-8');
}

function xmlResponse($payload, int $status = 200)
{
    http_response_code($status);
    header('Content-Type: text/xml; charset=utf-8');
    header('Cache-Control: no-store');
    header('X-Content-Type-Options: nosniff');
    $json = json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
    echo '<?xml version="1.0"?>'
        . '<methodResponse><params><param><value><struct><member><name>real</name><value><string>'
        . xmlEscape($json)
        . '</string></value></member></struct></value></param></params></methodResponse>';
    exit;
}

function faultResponse(int $code, string $message, int $status = 500)
{
    http_response_code($status);
    header('Content-Type: text/xml; charset=utf-8');
    header('Cache-Control: no-store');
    header('X-Content-Type-Options: nosniff');
    echo '<?xml version="1.0"?>'
        . '<methodResponse><fault><value><struct>'
        . '<member><name>faultCode</name><value><int>' . $code . '</int></value></member>'
        . '<member><name>faultString</name><value><string>' . xmlEscape($message) . '</string></value></member>'
        . '</struct></value></fault></methodResponse>';
    exit;
}

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo json_encode(['service' => 'Vaktpost XMLAPI Lab', 'endpoint' => '/xmlrpc.php', 'synthetic' => true, 'executes_submitted_code' => false, 'methods' => ['pfsense.exec_php']], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: GET, POST');
    http_response_code(405);
    exit;
}

$declaredLength = (int) ($_SERVER['CONTENT_LENGTH'] ?? 0);
if ($declaredLength > MAX_BODY_BYTES) {
    http_response_code(413);
    exit('Request too large');
}

$authorization = headerValue('Authorization');
if ($authorization === null || !str_starts_with($authorization, 'Basic ')) {
    header('WWW-Authenticate: Basic realm="Vaktpost XMLAPI Lab"');
    http_response_code(401);
    exit('Authentication required');
}

$decodedCredentials = base64_decode(substr($authorization, 6), true);
if ($decodedCredentials === false || !str_contains($decodedCredentials, ':')) {
    http_response_code(401);
    exit('Authentication required');
}
[$username, $password] = explode(':', $decodedCredentials, 2);
$expectedPassword = getenv('VAKTPOST_DEMO_PASSWORD') ?: 'vaktpost-demo';
if (!in_array($username, XmlApiSimulator::SCENARIOS, true) || !hash_equals($expectedPassword, $password)) {
    http_response_code(401);
    exit('Authentication required');
}

$body = file_get_contents('php://input');
if (!is_string($body) || strlen($body) > MAX_BODY_BYTES) {
    http_response_code(413);
    exit('Request too large');
}
if (preg_match('/<methodName>\s*pfsense\.exec_php\s*<\/methodName>/', $body) !== 1) {
    faultResponse(-32601, 'Only pfsense.exec_php is available in this simulator');
}
if (preg_match('/<string>([\s\S]*?)<\/string>/', $body, $matches) !== 1) {
    faultResponse(-32602, 'Missing PHP snippet parameter');
}

$secure = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') || (headerValue('X-Forwarded-Proto') === 'https');
session_name('VAKTPOSTLAB');
session_set_cookie_params(['lifetime' => 1800, 'path' => '/', 'secure' => $secure, 'httponly' => true, 'samesite' => 'Lax']);
session_start();

$completed = $_SESSION['completed_updates'] ?? [];
if (!is_array($completed)) {
    $completed = [];
}
$simulator = new XmlApiSimulator();
$result = $simulator->respond(xmlUnescape($matches[1]), $username, $completed);

if (isset($result['fault'])) {
    faultResponse($result['fault']['code'], $result['fault']['message']);
}
if (isset($result['completed_update'])) {
    $_SESSION['completed_updates'][$result['completed_update']] = true;
}
xmlResponse($result['payload'] ?? null);

