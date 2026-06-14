/* eslint-disable no-param-reassign */
/* eslint-disable no-underscore-dangle */
/* eslint-disable security/detect-object-injection */
import { MDCLinearProgress } from '@material/linear-progress'
import { dom, append } from './dom.js'
import { LinearProgress } from './LinearProgress.js'
import { DataTablePagination } from './DataTablePagination.js'
import { formats } from './formats.js'

const widthClasses = {
  '10%': 'width10p',
  '20%': 'width20p',
  '30%': 'width30p',
  '40%': 'width40p',
  '50%': 'width50p',
  '60%': 'width60p',
  '70%': 'width70p',
}

export class DataTable {
  constructor({
    html,
    fatherElement,
    tableName,
    labelRowsPerPage,
    columns = [],
    columnsHeaders = {},
    orderBys = {},
    defaultOrderBysStr = '',
    columnTypes = {},
    columnsFormats = {},
    locale = 'pt-BR',
    columnsWidths = {},
    limit = 25,
    offset = 0,
  }) {
    this.html = html
    this.tableName = tableName
    this.columnTypes = columnTypes
    this.columnsFormats = columnsFormats
    this.columnsWidths = columnsWidths
    this.columnsHeaders = columnsHeaders
    this._columns = columns
    this._orderBys = orderBys
    this._limit = limit
    this._offset = offset
    this.defaultLimit = limit
    this.defaultOffset = offset
    this.locale = locale
    const { domElement: domLinearProgressElement } = new LinearProgress()
    this.domLinearProgressElement = domLinearProgressElement
    this.linearProgress = new MDCLinearProgress(domLinearProgressElement)
    const mainDataTable = this
    this.pagination = new DataTablePagination({
      labelRowsPerPage,
      limit,
      offset,
      updateLimitOffset: (newLimit, newOffset) => {
        const { defaultLimit } = this
        const { defaultOffset } = this
        mainDataTable.limit = newLimit
        mainDataTable.offset = newOffset
        const url = new URL(window.location.href)
        const urlLimit = (url.searchParams.get('limit') && Number(url.searchParams.get('limit'))) || defaultLimit
        const urlOffset = (url.searchParams.get('offset') && Number(url.searchParams.get('offset'))) || defaultOffset
        if (urlLimit !== newLimit || urlOffset !== newOffset) {
          if (urlLimit !== newLimit) {
            url.searchParams.set('limit', newLimit)
          }
          if (urlOffset !== newOffset) {
            url.searchParams.set('offset', newOffset)
          }
          if (newLimit === defaultLimit) {
            url.searchParams.delete('limit')
          }
          if (newOffset === defaultOffset) {
            url.searchParams.delete('offset')
          }
          window.history.pushState({ html: this.html, pageTitle: document.getElementsByTagName('title')[0].innerHTML }, '', url.toString())
        }
        return mainDataTable.refresh()
      },
    })
    this.domPaginationElement = this.pagination.domElement
    this.fatherElement = fatherElement
    this.defaultOrderBysStr = defaultOrderBysStr
    this.init()
  }

  get columns() {
    return this._columns
  }

  set columns(columns) {
    this._columns = columns
  }

  get orderBys() {
    return this._orderBys
  }

  set orderBys(orderBys) {
    this._orderBys = orderBys
  }

  get limit() {
    return this._limit
  }

  set limit(limit) {
    this._limit = limit
  }

  get offset() {
    return this._offset
  }

  set offset(offset) {
    this._offset = offset
  }

  header(column) {
    const orderBysKeys = Object.keys(this.orderBys)
    const orderBysPosition = orderBysKeys.reduce((pv, cv, ci) => {
      pv[cv] = ci + 1
      return pv
    }, {})
    const useSuffix = orderBysKeys.length > 1
    if (!useSuffix || !orderBysPosition[column]) {
      return this.columnsHeaders[column] || column
    }
    return `${this.columnsHeaders[column] || column} (${orderBysPosition[column]})`
  }

  /**
   * Initialize dom table
   */
  init() {
    const orderBysObjToStr = (orderBys) => Object.entries(orderBys).map(([key, order]) => (order === 'descending' ? `desc(${key})` : `asc(${key})`)).join(',')
    const {
      tableName, columns, orderBys, columnTypes, columnsWidths,
    } = this
    const table = dom({
      tag: 'table',
      classes: ['mdc-data-table__table'],
      attributes: {
        role: 'table',
        'aria-label': tableName,
      },
    })
    const tHead = dom({ tag: 'thead' })
    append(tHead, columns.reduce((headerRow, column) => {
      const thClasses = [
        'mdc-data-table__header-cell',
        'mdc-data-table__header-cell--with-sort',
      ]
      if (orderBys[column]) {
        thClasses.push('mdc-data-table__header-cell--sorted')
      }
      if (columnTypes[column] === 'numeric') {
        thClasses.push('mdc-data-table__header-cell--numeric')
      }
      const th = dom({
        tag: 'th',
        classes: columnsWidths[column] ? thClasses.concat([widthClasses[columnsWidths[column]]]) : thClasses,
        attributes: {
          role: 'columnheader',
          scope: 'col',
          'aria-sort': orderBys[column] || 'none',
          'data-column-id': column,
        },
      })
      const headerCellWrapper = dom({
        tag: 'div',
        classes: ['mdc-data-table__header-cell-wrapper'],
      })
      const contentDiv = dom({
        tag: 'div',
        innerText: this.header(column),
      })
      const sortButton = dom({
        tag: 'button',
        classes: ['mdc-icon-button', 'material-icons', 'mdc-data-table__sort-icon-button'],
        attributes: {
          'aria-label': `Sort by ${column}`,
          'aria-describedby': `${column}-status-label`,
        },
        innerText: orderBys[column] === 'descending' ? 'arrow_downward' : 'arrow_upward',
      })
      sortButton.onclick = (ev) => {
        let nextButton = 'arrow_upward'
        if (ev.target.innerText === 'arrow_upward') {
          nextButton = 'arrow_downward'
        } else if (ev.target.innerText === 'arrow_downward') {
          nextButton = ''
        }
        ev.target.innerText = nextButton
        const thRef = sortButton.parentElement.parentElement
        if (nextButton) {
          thRef.classList.add('mdc-data-table__header-cell--sorted')
          if (nextButton === 'arrow_upward') {
            orderBys[column] = 'ascending'
          } else {
            orderBys[column] = 'descending'
          }
        } else {
          thRef.classList.remove('mdc-data-table__header-cell--sorted')
          delete orderBys[column]
        }
        const tr = sortButton.parentElement.parentElement.parentElement
        for (const thChildRef of tr.children) {
          const thColumn = thChildRef.attributes.getNamedItem('data-column-id').value
          const div = (columnTypes[thColumn] === 'numeric') ? thChildRef.firstElementChild.children[1] : thChildRef.firstElementChild.children[0]
          div.innerText = this.header(thColumn)
        }
        const url = new URL(window.location.href)
        const newOrderBysStr = orderBysObjToStr(this.orderBys)
        const currentOrderBysStr = url.searchParams.get('sort_by')
        if ((newOrderBysStr !== currentOrderBysStr) || !newOrderBysStr) {
          if (!newOrderBysStr || (newOrderBysStr === this.defaultOrderBysStr)) {
            url.searchParams.delete('sort_by')
          } else {
            url.searchParams.set('sort_by', newOrderBysStr)
          }
          window.history.pushState({ html: this.html, pageTitle: document.getElementsByTagName('title')[0].innerHTML }, '', url.toString())
        }
        return this.refresh()
      }
      const sortLabel = dom({
        tag: 'div',
        classes: ['mdc-data-table__sort-status-label'],
        attributes: {
          'aria-hidden': 'true',
          id: `${column}-status-label`,
        },
      })
      if (columnTypes[column] === 'numeric') {
        append(headerCellWrapper, sortButton)
        append(headerCellWrapper, contentDiv)
      } else {
        append(headerCellWrapper, contentDiv)
        append(headerCellWrapper, sortButton)
      }
      append(headerCellWrapper, sortLabel)
      append(th, headerCellWrapper)
      return append(headerRow, th)
    }, dom({
      tag: 'tr',
      attributes: {
        role: 'rowheader',
      },
    })))
    const tBody = dom({
      tag: 'tbody',
      classes: ['mdc-data-table__content'],
    })
    append(table, tHead)
    append(table, tBody)

    /**
     * @type {HTMLTableElement}
     */
    this.domTableContainerElement = dom({
      tag: 'div',
      classes: ['mdc-data-table__table-container'],
      children: [
        table,
        this.domLinearProgressElement,
      ],
    })
    /**
     * @type {HTMLTableElement}
     */
    this.domTableElement = table

    /**
     * @type {HTMLTableSectionElement}
     */
    this.domTableBody = tBody

    /**
     * @type {HTMLTableElement}
     */
    this.domElement = dom({
      tag: 'div',
      classes: ['mdc-data-table'],
      children: [
        this.domTableContainerElement,
        this.domPaginationElement,
      ],
    })
    if (this.fatherElement) {
      this.fatherElement.appendChild(this.domElement)
    }
  }

  /**
   * Fill dom table with data
   * @param {*[]} dataRows
   */
  populateTable(dataRows) {
    this.domTableBody.innerHTML = ''
    for (let i = 0; i < dataRows.length; i++) {
      const dataRow = dataRows[i]
      append(this.domTableBody, this.columns.reduce((tableRow, column, columnIndex) => {
        const classes = ['mdc-data-table__cell']
        let value = dataRow[column]
        if (this.columnsFormats[column]) {
          value = this.columnsFormats[column](dataRow[column])
        } else if (formats[column]) {
          value = formats[column](this.locale, dataRow[column])
        }
        const attributes = {
          role: 'cell',
          'data-column-id': column,
          locale: this.locale,
          title: value,
        }
        if (columnIndex === 0) {
          attributes.scope = 'row'
        }
        if (this.columnTypes[column] === 'numeric') {
          classes.push('mdc-data-table__cell--numeric')
        }
        const cell = dom({
          tag: 'td',
          innerText: value,
          classes: this.columnsWidths[column] ? classes.concat([widthClasses[this.columnsWidths[column]]]) : classes,
          attributes,
        })
        return append(tableRow, cell)
      }, dom({
        tag: 'tr',
        classes: ['mdc-data-table__row'],
        attributes: {
          role: 'row',
          'aria-rowindex': String(i),
        },
      })))
    }
  }

  async refresh() {
    try {
      await this.beforeFetchData()
      const { rows, total } = await this.fetchData()
      this.populateTable(rows)
      this.pagination.refresh(rows.length, total, this.limit, this.offset)
      this.afterFetchData(null)
    } catch (err) {
      // eslint-disable-next-line no-console
      console.error(err)
      this.domTableContainerElement.innerText = 'Error fetching data. Please refresh the page'
      this.afterFetchData(err)
    }
  }

  async beforeFetchData() {
    this.linearProgress.open()
    this.domTableBody.innerHTML = ''
  }

  async fetchData() {
    return {
      rows: [],
      total: 0,
    }
  }

  async afterFetchData(err) {
    this.linearProgress.close()
    if (err) {
      this.handleFetchDataError(err)
    }
  }

  async handleFetchDataError(err) {
    // eslint-disable-next-line no-console
    console.error(err)
  }
}
