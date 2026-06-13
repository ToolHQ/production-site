/* eslint-disable security/detect-object-injection */
import { MDCLinearProgress } from '@material/linear-progress'
import { dom, append } from './dom.js'
import { LinearProgress } from './LinearProgress.js'
import { formats, widthClasses } from './formats.js'

export class SimpleDataTable {
  constructor({
    html,
    fatherElement,
    tableName,
    locale = 'pt-BR',
    columnsWidths = {},
  }) {
    this.html = html
    this.tableName = tableName
    this.locale = locale
    this.columns = []
    this.columnsWidths = columnsWidths
    const { domElement: domLinearProgressElement } = new LinearProgress()
    this.domLinearProgressElement = domLinearProgressElement
    this.linearProgress = new MDCLinearProgress(domLinearProgressElement)
    this.fatherElement = fatherElement
    this.init()
  }

  /**
   * Initialize dom table
   */
  init() {
    if (this.domElement) {
      this.domElement.innerHTML = ''
    }
    const { tableName, columns, columnsWidths } = this
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
      const th = dom({
        tag: 'th',
        classes: columnsWidths[column] ? thClasses.concat([widthClasses[columnsWidths[column]]]) : thClasses,
        attributes: {
          role: 'columnheader',
          scope: 'col',
          'data-column-id': column,
        },
      })
      const headerCellWrapper = dom({
        tag: 'div',
        classes: ['mdc-data-table__header-cell-wrapper'],
      })
      const contentDiv = dom({
        tag: 'div',
        innerText: column,
      })
      append(headerCellWrapper, contentDiv)
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
      ],
    })
    if (this.fatherElement) {
      this.fatherElement.appendChild(this.domElement)
    }
    this.linearProgress.close()
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
        const value = formats[column] ? formats[column](this.locale, dataRow[column]) : dataRow[column]
        const attributes = {
          role: 'cell',
          'data-column-id': column,
          locale: this.locale,
          title: value,
        }
        if (columnIndex === 0) {
          attributes.scope = 'row'
        }
        const cell = dom({
          tag: 'td',
          innerText: value,
          classes: ['mdc-data-table__cell'],
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

  async refresh(queryInput) {
    try {
      await this.beforeFetchData()
      const { rows } = await this.fetchData(queryInput)
      this.columns = []
      for (const row of rows) {
        this.columns = [...new Set(this.columns.concat(Object.keys(row)))]
      }
      this.init()
      this.populateTable(rows)
      this.afterFetchData(null)
    } catch (err) {
      this.domTableContainerElement.innerText = err.message
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
