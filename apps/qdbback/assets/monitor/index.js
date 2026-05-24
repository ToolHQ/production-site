import { Tabs } from './components/Tabs.js'
import { initScroll } from './scrollHelper.js'
import { initRequestsTable, initLogsTable } from './tables.js'
import { initStatus } from './statusController.js'
import { getUrlState } from './urlState.js'
import { initTopBar } from './topBar.js'
import { init as initSqlTab } from './sqlTab.js'

(() => {
  initScroll()

  const topBar = document.getElementById('topbar')
  const topBarNormal = document.getElementById('topbar-normal')
  const topBarSearch = document.getElementById('topbar-search')

  const requestsTableContainer = document.getElementById('requestsTable')
  const logsTableContainer = document.getElementById('logsTable')
  const statusTabContainer = document.getElementById('statusTab')

  const acceptLanguages = async () => {
    const result = await fetch('/accept-languages')
    const jsonObj = await result.json()
    return jsonObj.languages || []
  }

  document.addEventListener('DOMContentLoaded', async () => {
    const { outerHTML: html } = document.querySelector('html')
    const {
      part, limit, offset, orderBysStr, logsTab, requestsTab,
    } = getUrlState()
    const languages = await acceptLanguages()
    const locale = localStorage.getItem('user-prefered-locale') || (languages[0] && languages[0].locale) || 'pt-BR'
    // console.log({ locale, languages })

    initTopBar(topBarNormal, topBarSearch, locale)
    const requestsTable = initRequestsTable({
      html, fatherElement: requestsTableContainer, part, limit, offset, orderBysStr, requestsTab, locale,
    })
    const logsTable = initLogsTable({
      html, fatherElement: logsTableContainer, part, limit, offset, orderBysStr, logsTab, locale,
    })
    const sqlTabContainer = initSqlTab({ html })

    const tabs = new Tabs({
      html,
      tabs: [
        {
          icon: 'sync_alt',
          text: 'Requests',
          domElement: requestsTableContainer,
          path: '/monitor/requests',
        },
        {
          icon: 'notes',
          text: 'Logs',
          domElement: logsTableContainer,
          path: '/monitor/logs',
        },
        {
          icon: 'mode',
          text: 'SQL',
          domElement: sqlTabContainer,
          path: '/monitor/sql',
        },
        {
          icon: 'settings',
          text: 'Status',
          domElement: statusTabContainer,
          path: '/monitor/status',
        },
      ],
    })
    topBar.appendChild(tabs.domElement)
    await requestsTable.refresh()
    await logsTable.refresh()
    await initStatus({
      html,
    })
  }, false)
})()
