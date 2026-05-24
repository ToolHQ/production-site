/**
 * Heuristic threat/scanner classification for honeypot requests.
 * Tags are comma-separated, sorted (stable for SQLite GROUP BY).
 */

const PATH_RULES = [
  { tag: 'env-leak', re: /\.env|\.git\/|wp-config|config\.json|\.aws\/|id_rsa/i },
  { tag: 'phpunit-rce', re: /phpunit|eval-stdin\.php/i },
  { tag: 'phpmyadmin', re: /phpmyadmin|\/pma\b/i },
  { tag: 'wordpress', re: /wp-content|wp-includes|wp-admin|wlwmanifest|wordpress/i },
  { tag: 'laravel-rce', re: /_ignition|laravel/i },
  { tag: 'router-exploit', re: /boaform|formLogin|setup\.cgi/i },
  { tag: 'java-probe', re: /jsonws|invoke|actuator|jmx-console|weblogic/i },
  { tag: 'exchange-probe', re: /autodiscover|\/owa\b|exchange/i },
  { tag: 'solr-probe', re: /solr|admin\/cores/i },
  { tag: 'shell-probe', re: /shell\.|cmd\.exe|\/bin\/sh|\/bin\/bash/i },
  { tag: 'path-traversal', re: /\.\.|%2e%2e|%252e/i },
  { tag: 'sql-injection', re: /union\+select|information_schema|'or'1'='1/i },
]

const UA_RULES = [
  { tag: 'scanner:zgrab', re: /zgrab/i },
  { tag: 'scanner:censys', re: /censysinspect|censys/i },
  { tag: 'scanner:masscan', re: /masscan/i },
  { tag: 'scanner:nmap', re: /nmap/i },
  { tag: 'scanner:shodan', re: /shodan/i },
  { tag: 'scanner:bot', re: /bot|crawler|spider|scan/i },
]

/**
 * @param {{ path?: string, method?: string, userAgent?: string, statusCode?: number }} input
 * @returns {string}
 */
export const classifyRequest = ({
  path = '/',
  method = 'GET',
  userAgent = '',
  statusCode,
}) => {
  const tags = new Set()
  const normalizedPath = path || '/'
  const ua = userAgent || ''

  for (const { tag, re } of PATH_RULES) {
    if (re.test(normalizedPath)) {
      tags.add(tag)
    }
  }
  for (const { tag, re } of UA_RULES) {
    if (re.test(ua)) {
      tags.add(tag)
    }
  }

  if (normalizedPath === '/' || normalizedPath === '/index.html') {
    tags.add('probe:root')
  }
  if (normalizedPath === '/favicon.ico') {
    tags.add('misc:favicon')
  }
  if (method === 'POST' && normalizedPath === '/') {
    tags.add('probe:post-root')
  }
  if (statusCode === 404 && tags.size === 1 && tags.has('probe:root')) {
    tags.add('probe:404')
  }

  if (tags.size === 0) {
    tags.add('unclassified')
  }

  return [...tags].sort().join(',')
}

export default { classifyRequest }
