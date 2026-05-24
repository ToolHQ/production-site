import { dom } from './components/dom.js'

const sugestions = [
  { field: 'id', keywords: ['id'], displayName: 'Id' },
  { field: 'timestamp', keywords: ['timestamp'], displayName: 'Timestamp' },
  { field: 'method', keywords: ['method'], displayName: 'Method' },
  { field: 'remoteHostname', keywords: ['remote', 'hostname', 'remote hostname'], displayName: 'Remote Hostname' },
]

let currentSugestions = []

const filterSugestions = (input = '') => {
  currentSugestions = []
  const newSugestions = []
  for (const sugestion of sugestions) {
    if (sugestion.keywords.some((keyword) => keyword.includes(String(input).toLowerCase()))) {
      newSugestions.push(sugestion)
    }
  }
  currentSugestions = newSugestions.sort((a, b) => {
    if (a.displayName > b.displayName) {
      return 1
    }
    if (a.displayName < b.displayName) {
      return -1
    }
    return 0
  })
}

const createLi = (tabindex, innerText) => dom({
  tag: 'li',
  classes: ['mdc-list-item'],
  attributes: {
    tabindex,
  },
  children: [
    dom({
      tag: 'span',
      classes: ['mdc-list-item__ripple'],
    }),
    dom({
      tag: 'span',
      classes: ['mdc-list-item__text'],
      innerText,
    }),
  ],
})

/**
 * @param {HTMLElement} ul
 * @param {HTMLElement} searchInput
 */
const updateSugestions = (ul, searchInput) => {
  filterSugestions(searchInput.value)
  // eslint-disable-next-line no-param-reassign
  ul.innerHTML = ''
  // eslint-disable-next-line no-param-reassign
  ul.style.display = (currentSugestions.length) ? 'block' : 'none'
  currentSugestions.forEach((sugestion, tabindex) => ul.appendChild(createLi(tabindex, sugestion.displayName)))
}

const toogleTopBar = (topBarNormal, topBarSearch) => {
  if (topBarSearch.style.display === 'none') {
    // eslint-disable-next-line no-param-reassign
    topBarSearch.style.display = 'block'
    // eslint-disable-next-line no-param-reassign
    topBarNormal.style.display = 'none'
  } else {
    // eslint-disable-next-line no-param-reassign
    topBarSearch.style.display = 'none'
    // eslint-disable-next-line no-param-reassign
    topBarNormal.style.display = 'block'
  }
}

const localeToDisplay = {
  en: 'English',
  'en-US': 'English',
  'pt-BR': 'Português Brasileiro',
  pt: 'Português Brasileiro',
}

const displayToLocale = {
  English: 'en-US',
  'Português Brasileiro': 'pt-BR',
}

const hideLanguagesOptions = (languagesUl) => {
  // eslint-disable-next-line no-param-reassign
  languagesUl.style.display = 'none'
}

const changeLanguage = (ev) => {
  const newLocale = displayToLocale[ev.target.innerText.trim()]
  localStorage.setItem('user-prefered-locale', newLocale)
  window.location.reload()
}

/**
 * @param {HTMLElement} topBarNormal
 * @param {HTMLElement} topBarSearch
 * @param {String} locale
 */
export const initTopBar = (topBarNormal, topBarSearch, locale) => {
  const searchButton = topBarNormal.querySelector('button[aria-label="Search"]')
  const closeSearchButton = topBarSearch.querySelector('button[aria-label="Close"]')

  const searchInput = topBarSearch.querySelector('#search-input')
  const sugestionUl = topBarSearch.querySelector('#search-list-options')

  const handleToogleTopBar = toogleTopBar.bind(null, topBarNormal, topBarSearch)

  // Changing Language
  const changeLanguageButton = topBarNormal.querySelector('button[aria-label="Change Language"]')
  const languagesUl = document.querySelector('#languages-options')
  const languagesFirstLi = document.querySelector('#languages-options > li:nth-child(1)')
  const languageSpan = topBarNormal.querySelector('#languageSelected')
  languageSpan.innerText = localeToDisplay[locale]
  const handleLanguagesOptions = hideLanguagesOptions.bind(null, languagesUl)

  changeLanguageButton.addEventListener('click', () => {
    languagesUl.style.display = 'block'
    languagesUl.focus()
    languagesFirstLi.focus()
  })

  document.querySelector('html').addEventListener('click', (ev) => {
    if (!ev.target.classList.contains('mdc-list-item')
      && !ev.target.classList.contains('mdc-list')
      && !ev.target.classList.contains('mdc-select__anchor') && languagesUl.style.display !== 'none' && languagesFirstLi !== document.activeElement) {
      handleLanguagesOptions()
    }
  })
  for (const li of languagesUl.children) {
    li.addEventListener('click', changeLanguage)
  }

  // Open and closing search toolbar
  searchButton.addEventListener('click', () => {
    handleToogleTopBar()
    topBarSearch.focus()
    searchInput.focus()
  })
  closeSearchButton.addEventListener('click', handleToogleTopBar)

  // Populates field 1
  searchInput.addEventListener('keydown', () => {
    updateSugestions(sugestionUl, searchInput)
  })
  searchInput.addEventListener('keyup', (ev) => {
    updateSugestions(sugestionUl, searchInput)
    if (ev.key === 'Enter' && currentSugestions.length === 1) {
      searchInput.disabled = true
    }
  })

  searchInput.addEventListener('blur', () => {
    handleToogleTopBar()
  })
}
