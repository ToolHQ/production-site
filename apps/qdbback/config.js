import os from 'os'

export const isProduction = os.hostname().endsWith('.ec2.internal')
// EC2 prod: 80/443 (scanners usam portas default). Dev local: 3000/3443 (sem root).
export const port = isProduction ? 80 : 3000
export const portHttps = isProduction ? 443 : 3443
export const portAdmin = 3500

// eslint-disable-next-line max-len
export const cspDefaultHeader = "default-src 'self'; style-src https://fonts.googleapis.com 'unsafe-inline' 'self'; font-src https://fonts.gstatic.com 'self'; report-uri /internal/csp-reports"
