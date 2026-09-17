<?php

declare(strict_types=1);

if (isset($_SERVER['SCRIPT_FILENAME']) && realpath((string) $_SERVER['SCRIPT_FILENAME']) === __FILE__) {
    http_response_code(404);
    exit;
}

/**
 * The newest version tag in the public GitHub repository.
 *
 * Looked up by the server, not the visitor's browser, so no page view reaches
 * GitHub. The answer is cached in the system temp directory: a found version
 * for an hour, a failed lookup for ten minutes. That keeps the site well under
 * GitHub's 60 unauthenticated requests an hour, and a GitHub outage costs
 * one short timeout per ten minutes rather than one per visitor.
 *
 * Tags are compared as versions, not by date or name order, and a leading "v"
 * is ignored. Anything that is not MAJOR.MINOR.PATCH (pre-releases included)
 * is skipped. With no usable tag the caller's fallback is returned.
 */
final class LatestRelease
{
    private const REPO = 'kladhest-se/vaktpost';
    private const TTL_FOUND = 3600;
    private const TTL_MISSING = 600;
    private const TIMEOUT = 3;

    public static function version(string $fallback): string
    {
        $cache = sys_get_temp_dir() . '/vaktpost-latest-release.json';
        $cached = self::readCache($cache);
        if ($cached !== null) {
            return $cached === '' ? $fallback : $cached;
        }
        $found = self::fetch() ?? '';
        self::writeCache($cache, $found);
        return $found === '' ? $fallback : $found;
    }

    private static function readCache(string $path): ?string
    {
        $raw = @file_get_contents($path);
        if ($raw === false) {
            return null;
        }
        $data = json_decode($raw, true);
        if (!is_array($data) || !is_string($data['version'] ?? null) || !is_int($data['at'] ?? null)) {
            return null;
        }
        $ttl = $data['version'] === '' ? self::TTL_MISSING : self::TTL_FOUND;
        return time() - $data['at'] < $ttl ? $data['version'] : null;
    }

    private static function writeCache(string $path, string $version): void
    {
        $tmp = $path . '.' . bin2hex(random_bytes(4));
        if (@file_put_contents($tmp, json_encode(['version' => $version, 'at' => time()])) !== false) {
            @rename($tmp, $path);
        }
    }

    private static function fetch(): ?string
    {
        $body = self::get('https://api.github.com/repos/' . self::REPO . '/tags?per_page=100');
        if ($body === null) {
            return null;
        }
        $tags = json_decode($body, true);
        if (!is_array($tags)) {
            return null;
        }
        $best = null;
        foreach ($tags as $tag) {
            $name = is_array($tag) && is_string($tag['name'] ?? null) ? $tag['name'] : '';
            if (preg_match('/^v?(\d+\.\d+\.\d+)$/', $name, $m) !== 1) {
                continue;
            }
            if ($best === null || version_compare($m[1], $best, '>')) {
                $best = $m[1];
            }
        }
        return $best;
    }

    private static function get(string $url): ?string
    {
        $headers = ['Accept: application/vnd.github+json', 'User-Agent: vaktpost-website'];
        if (function_exists('curl_init')) {
            $ch = curl_init($url);
            curl_setopt_array($ch, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_TIMEOUT => self::TIMEOUT,
                CURLOPT_CONNECTTIMEOUT => self::TIMEOUT,
                CURLOPT_HTTPHEADER => $headers,
                CURLOPT_FOLLOWLOCATION => false,
            ]);
            $body = curl_exec($ch);
            $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);
            return is_string($body) && $status === 200 ? $body : null;
        }
        if (!filter_var(ini_get('allow_url_fopen'), FILTER_VALIDATE_BOOL)) {
            return null;
        }
        $context = stream_context_create(['http' => [
            'header' => implode("\r\n", $headers),
            'timeout' => self::TIMEOUT,
            'ignore_errors' => true,
        ]]);
        $body = @file_get_contents($url, false, $context);
        $status = isset($http_response_header[0]) && preg_match('/\s(\d{3})\s/', $http_response_header[0], $m) === 1
            ? (int) $m[1] : 0;
        return is_string($body) && $status === 200 ? $body : null;
    }
}
