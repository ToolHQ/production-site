import { initSqlResultTable } from './tables.js'

const downloadBlob = (blob, filename) => {
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename || 'download'
  const clickHandler = () => {
    setTimeout(() => {
      URL.revokeObjectURL(url)
      this.removeEventListener('click', clickHandler)
    }, 150)
  }
  a.addEventListener('click', clickHandler, false)
  a.click()
  return a
}

export const init = ({ html }) => {
  const sqlTabContainer = document.getElementById('sqlTab')
  const sqlInput = document.getElementById('sqlInput')
  const sqlButton = document.getElementById('sqlButton')
  const sqlDownloadButton = document.getElementById('sqlDownloadButton')
  const sqlResultsTableContainer = document.getElementById('sqlResultsTable')

  const sqlResultsTable = initSqlResultTable({ html, fatherElement: sqlResultsTableContainer })
  sqlButton.addEventListener('click', async () => {
    await sqlResultsTable.refresh(sqlInput.value)
  })
  sqlDownloadButton.addEventListener('click', async () => {
    const result = await fetch('/api/monitor/sql', {
      method: 'POST',
      headers: {
        'Content-Type': 'text/plain',
      },
      body: sqlInput.value,
    })
    const filename = `${String(sqlInput.value).split(' ').map((t) => t.trim().replace(/\n| |\t/gi, '')).filter(Boolean)
      .join('_')}.json`
    const blob = await result.blob()
    return downloadBlob(blob, filename)
  })
  return sqlTabContainer
}
