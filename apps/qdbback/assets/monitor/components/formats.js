/* eslint-disable security/detect-object-injection */
export const microToMs = (_, micro) => `${(micro / 1000).toFixed(3)}ms`

const dateFormatters = {}
export const timestampFormat = (locale = 'pt-BR', isoDateStr) => {
  if (!dateFormatters[locale]) {
    dateFormatters[locale] = new Intl.DateTimeFormat(locale, {
      weekday: 'long',
      year: 'numeric',
      month: 'numeric',
      day: 'numeric',
      hour: 'numeric',
      minute: 'numeric',
      second: 'numeric',
      fractionalSecondDigits: 3,
      hour12: false,
    })
  }
  return dateFormatters[locale].format(new Date(isoDateStr))
}

export const formats = {
  timestamp: timestampFormat,
  timeElapsed: microToMs,
}

export const widthClasses = {
  '10%': 'width10p',
  '20%': 'width20p',
  '30%': 'width30p',
  '40%': 'width40p',
  '50%': 'width50p',
  '60%': 'width60p',
  '70%': 'width70p',
}
