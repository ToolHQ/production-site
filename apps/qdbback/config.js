import os from 'os'

export const port = 3000
export const portHttps = 3443
export const portAdmin = 3500
export const isProduction = os.hostname().endsWith('.ec2.internal')

// eslint-disable-next-line max-len
export const cspDefaultHeader = "default-src 'self'; style-src https://fonts.googleapis.com 'unsafe-inline' 'self'; font-src https://fonts.gstatic.com 'self'; report-uri /internal/csp-reports"
