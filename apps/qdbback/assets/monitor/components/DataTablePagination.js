import { dom } from './dom.js'

export class DataTablePagination {
  constructor({
    labelRowsPerPage,
    limit,
    offset,
    updateLimitOffset,
  } = {}) {
    this.labelRowsPerPage = labelRowsPerPage
    this.pagLimit = limit
    this.pagOffset = offset
    this.updateLimitOffset = updateLimitOffset
    this.init()
  }

  initList() {
    const list = [10, 20, 25, 50].map((option) => {
      const firstSpan = dom({
        tag: 'span',
        classes: ['mdc-list-item__ripple'],
      })
      const secondSpan = dom({
        tag: 'span',
        classes: ['mdc-list-item__text'],
        innerText: option,
      })
      const perPageItem = dom({
        tag: 'li',
        classes: ['mdc-list-item'],
        attributes: {
          role: 'option',
        },
        children: [
          firstSpan,
          secondSpan,
        ],
      })
      perPageItem.onclick = (ev) => {
        this.pagLimit = Number(ev.target.innerText)
        this.pagOffset = 0
        this.domPaginationTotalElement.innerText = ''
        this.domSelectedPerPageElement.innerText = ev.target.innerText
        this.domPerPageList.classList.remove('mdc-menu-surface--open')
        this.domPerPageList.classList.remove('mdc-menu-surface--is-open-below')
        return this.updateLimitOffset(this.pagLimit, this.pagOffset)
      }
      return perPageItem
    })
    // list[0].classList.add('mdc-menu-item--selected')
    // list[0].setAttribute('aria-selected', 'true')
    return list
  }

  // eslint-disable-next-line class-methods-use-this
  iconButton(innerText) {
    const el = dom({
      tag: 'button',
      classes: ['mdc-icon-button', 'material-icons', 'mdc-data-table__pagination-button'],
      children: [
        dom({
          tag: 'div',
          classes: ['mdc-button__icon'],
          innerText,
        }),
      ],
    })
    el.disabled = true
    return el
  }

  init() {
    this.domPaginationTotalElement = dom({
      tag: 'div',
      classes: ['mdc-data-table__pagination-total'],
      attributes: {
        id: 'pagination-total',
      },
      innerText: '',
    })
    this.domSelectedPerPageElement = dom({
      tag: 'span',
      classes: ['mdc-select__selected-text'],
      attributes: {
        id: 'demo-pagination-select',
      },
      innerText: `${this.pagLimit}`,
    })
    this.domButtonFirstPageElement = this.iconButton('first_page')
    this.domButtonFirstPageElement.onclick = () => {
      this.pagOffset = 0
      this.domPaginationTotalElement.innerText = ''
      return this.updateLimitOffset(this.pagLimit, this.pagOffset)
    }
    this.domButtonPreviousPageElement = this.iconButton('chevron_left')
    this.domButtonPreviousPageElement.onclick = () => {
      this.pagOffset -= this.pagLimit
      this.domPaginationTotalElement.innerText = ''
      return this.updateLimitOffset(this.pagLimit, this.pagOffset)
    }
    this.domButtonNextPageElement = this.iconButton('chevron_right')
    this.domButtonNextPageElement.onclick = () => {
      this.pagOffset += this.pagLimit
      this.domPaginationTotalElement.innerText = ''
      return this.updateLimitOffset(this.pagLimit, this.pagOffset)
    }
    this.domButtonLastPageElement = this.iconButton('last_page')
    this.domButtonLastPageElement.onclick = () => {
      this.pagOffset = Math.floor(this.pagTotal / this.pagLimit) * this.pagLimit
      this.domPaginationTotalElement.innerText = ''
      return this.updateLimitOffset(this.pagLimit, this.pagOffset)
    }

    const ul = dom({
      tag: 'ul',
      classes: ['mdc-list'],
      children: this.initList(),
    })
    this.domPerPageList = dom({
      tag: 'div',
      classes: ['mdc-select__menu', 'mdc-menu', 'mdc-menu-surface', 'mdc-menu-surface--fullwidth'],
      attributes: {
        role: 'listbox',
      },
      children: [
        ul,
      ],
    })

    this.domPerPageButtonElement = dom({
      tag: 'div',
      classes: ['mdc-select__anchor'],
      attributes: {
        role: 'button',
        'aria-haspopup': 'listbox',
        'aria-labelledby': 'demo-pagination-select',
        tabindex: '0',
      },
      children: [
        this.domSelectedPerPageElement,
        dom({
          tag: 'span',
          classes: ['mdc-select__dropdown-icon'],
          children: [
            dom({
              tag: 'svg',
              classes: ['mdc-select__dropdown-icon-graphic'],
              attributes: {
                viewBox: '7 10 10 5',
              },
              children: [
                dom({
                  tag: 'polygon',
                  classes: ['mdc-select__dropdown-icon-inactive'],
                  attributes: {
                    stroke: 'none',
                    'fill-rule': 'evenodd',
                    points: '7 10 12 15 17 10',
                  },
                }),
                dom({
                  tag: 'polygon',
                  classes: ['mdc-select__dropdown-icon-active'],
                  attributes: {
                    stroke: 'none',
                    'fill-rule': 'evenodd',
                    points: '7 15 12 10 17 15',
                  },
                }),
              ],
            }),
          ],
        }),
        dom({
          tag: 'span',
          classes: ['mdc-notched-outline', 'mdc-notched-outline--notched'],
          children: [
            dom({
              tag: 'span',
              classes: ['mdc-notched-outline__leading'],
            }),
            dom({
              tag: 'span',
              classes: ['mdc-notched-outline__trailing'],
            }),
          ],
        }),
      ],
    })
    this.domPerPageButtonElement.onclick = () => {
      this.domPerPageList.classList.add('mdc-menu-surface--open')
      this.domPerPageList.classList.add('mdc-menu-surface--is-open-below')
    }
    document.querySelector('html').addEventListener('click', (ev) => {
      if (!ev.target.classList.contains('mdc-list-item') && !ev.target.classList.contains('mdc-list') && !ev.target.classList.contains('mdc-select__anchor')) {
        this.domPerPageList.classList.remove('mdc-menu-surface--open')
        this.domPerPageList.classList.remove('mdc-menu-surface--is-open-below')
      }
    })

    const domElement = dom({
      tag: 'div',
      classes: ['mdc-data-table__pagination'],
      children: [
        dom({
          tag: 'div',
          classes: ['mdc-data-table__pagination-trailing'],
          children: [
            dom({
              tag: 'div',
              classes: ['mdc-data-table__pagination-rows-per-page'],
              children: [
                dom({
                  tag: 'div',
                  classes: ['mdc-data-table__pagination-rows-per-page-label'],
                  innerText: this.labelRowsPerPage,
                }),
                dom({
                  tag: 'div',
                  classes: ['mdc-select', 'mdc-select--outlined', 'mdc-select--no-label', 'mdc-data-table__pagination-rows-per-page-select'],
                  children: [
                    this.domPerPageButtonElement,
                    this.domPerPageList,
                  ],
                }),
              ],
            }),
            dom({
              tag: 'div',
              classes: ['mdc-data-table__pagination-navigation'],
              children: [
                this.domPaginationTotalElement,
                this.domButtonFirstPageElement,
                this.domButtonPreviousPageElement,
                this.domButtonNextPageElement,
                this.domButtonLastPageElement,
              ],
            }),
          ],
        }),
      ],
    })
    this.domElement = domElement
  }

  refresh(rowsLength, total, limit, offset) {
    this.pagLimit = limit
    this.pagOffset = offset
    this.pagTotal = total
    const itemLower = offset + 1
    const itemUpper = offset + (rowsLength || limit)
    this.domPaginationTotalElement.innerText = total === 0 ? '' : `${itemUpper > itemLower ? `${itemLower}-${itemUpper}` : itemLower} de ${total}`
    this.domSelectedPerPageElement.innerText = limit
    const after = total - (Math.min(offset, total) + rowsLength)
    if (offset) {
      this.domButtonFirstPageElement.disabled = false
      this.domButtonPreviousPageElement.disabled = false
    } else {
      this.domButtonFirstPageElement.disabled = true
      this.domButtonPreviousPageElement.disabled = true
    }
    if (after > 0) {
      this.domButtonNextPageElement.disabled = false
      this.domButtonLastPageElement.disabled = false
    } else {
      this.domButtonNextPageElement.disabled = true
      this.domButtonLastPageElement.disabled = true
    }
  }
}
