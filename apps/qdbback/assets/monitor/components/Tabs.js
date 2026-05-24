import { dom } from './dom.js'

export class Tabs {
  constructor({ tabs = [], html }) {
    this.tabs = []
    this.indicators = []
    this.tabsDomElements = []
    this.displays = []
    this.paths = []
    this.html = html

    const url = new URL(window.location.href)
    for (const tab of tabs) {
      this.initTab(tab.icon, tab.text, url.pathname.endsWith(tab.path), tab.domElement, tab.path)
    }
    this.init()
  }

  initTab(icon, text, active = false, domElement, path) {
    const index = this.tabs.length
    const indicator = dom({
      tag: 'span',
      classes: active ? ['mdc-tab-indicator', 'mdc-tab-indicator--active'] : ['mdc-tab-indicator'],
      children: [
        dom({
          tag: 'span',
          classes: ['mdc-tab-indicator__content', 'mdc-tab-indicator__content--underline'],
        }),
      ],
    })
    const ripple = dom({
      tag: 'span',
      classes: ['mdc-tab__ripple'],
    })
    const tab = dom({
      tag: 'button',
      classes: active ? ['mdc-tab', 'mdc-tab--active'] : ['mdc-tab'],
      attributes: {
        role: 'tab',
        'aria-selected': String(active),
        tabindex: String(index),
      },
      children: [
        dom({
          tag: 'span',
          classes: ['mdc-tab__content'],
          children: [
            dom({
              tag: 'span',
              classes: ['mdc-tab__icon', 'material-icons'],
              attributes: {
                'aria-hidden': 'true',
              },
              innerText: icon,
            }),
            dom({
              tag: 'span',
              classes: ['mdc-tab__text-label'],
              innerText: text,
            }),
          ],
        }),
        indicator,
        ripple,
      ],
    })
    ripple.onclick = () => {
      indicator.classList.add('mdc-tab-indicator--active')
      tab.classList.add('mdc-tab--active')
      tab.setAttribute('aria-selected', 'true')
      // eslint-disable-next-line no-param-reassign
      domElement.style = `display:${this.displays[index]}`
      for (let i = 0; i < this.tabs.length; i++) {
        if (i !== index) {
          this.indicators[i].classList.remove('mdc-tab-indicator--active')
          this.tabs[i].classList.remove('mdc-tab--active')
          this.tabs[i].setAttribute('aria-selected', 'false')
          this.tabsDomElements[i].style = 'display:none'
        }
      }

      const url = new URL(window.location.href)
      if (url.pathname !== path) {
        url.pathname = path
        window.history.pushState({ html: this.html, pageTitle: document.getElementsByTagName('title')[0].innerHTML }, '', url.toString())
      }
    }
    this.tabs.push(tab)
    this.indicators.push(indicator)
    this.tabsDomElements.push(domElement)
    this.displays.push('block')
    this.paths.push(path)
    if (!active) {
      // eslint-disable-next-line no-param-reassign
      domElement.style = 'display:none'
    }
    return tab
  }

  init() {
    this.domElement = dom({
      tag: 'div',
      classes: ['mdc-tab-bar'],
      attributes: {
        role: 'tablist',
      },
      children: [
        dom({
          tag: 'div',
          classes: ['mdc-tab-scroller'],
          children: [
            dom({
              tag: 'div',
              classes: ['mdc-tab-scroller__scroll-area'],
              children: [
                dom({
                  tag: 'div',
                  classes: ['mdc-tab-scroller__scroll-content'],
                  children: this.tabs,
                }),
              ],
            }),
          ],
        }),
      ],
    })
  }
}
