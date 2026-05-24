/* eslint-disable class-methods-use-this */
import * as chartjs from 'chart.js'

import { SimpleDataTable } from './components/SimpleDataTable.js'

const {
  Legend,
  Title,
  Tooltip,
  Chart,
  ArcElement,
  DoughnutController,
} = chartjs
Chart.register(
  Legend,
  Title,
  Tooltip,
  ArcElement,
  DoughnutController,
)

const Utils = {
  CHART_COLORS: {
    red: 'rgb(255, 99, 132)',
    orange: 'rgb(255, 159, 64)',
    yellow: 'rgb(255, 205, 86)',
    green: 'rgb(75, 192, 192)',
    blue: 'rgb(54, 162, 235)',
    purple: 'rgb(153, 102, 255)',
    grey: 'rgb(201, 203, 207)',
  },
}

class StatusTable extends SimpleDataTable {
  async fetchData() {
    const { processes: { list } } = await (await fetch('/api/monitor/status')).json()
    const rows = list.map(({
      pid, name, params, started, state, rss, rssPercentage, cpu,
    }) => ({
      pid,
      process: `${name} ${params}`,
      started,
      state,
      rss,
      rssPercentage,
      cpu,
    }))
    return { total: list.length, rows }
  }
}

const initStatusTable = ({
  html, fatherElement, locale,
}) => new StatusTable({
  html,
  fatherElement,
  tableName: 'System Processes',
  locale,
  columnsWidths: {
    process: '60%',
  },
})

const fetchSystemInformation = async () => {
  const result = await fetch('/api/monitor/status')
  const jsonObj = await result.json()
  return jsonObj
}

const truncate = (source, size) => (source.length > size ? `${source.slice(0, size - 1)}…` : source)

export const initStatus = async ({
  html,
  locale,
}) => {
  const { processes: { list = [] } } = await fetchSystemInformation()

  const dataContent = list.slice(0, 20).reduce((acc, process) => {
    const cmd = `${process.command} ${process.params}`
    acc.tooltipLabels.push(cmd)
    acc.legendLabels.push(truncate(cmd, 50))
    return acc
  }, {
    tooltipLabels: [],
    legendLabels: [],
  })

  const data = {
    labels: dataContent.legendLabels,
    datasets: [
      {
        label: 'Dataset 1',
        data: list.slice(0, 20).map((process) => process.memRss),
        backgroundColor: Object.values(Utils.CHART_COLORS),
      },
    ],
  }

  const statusTableContainer = document.getElementById('statusTable')
  const statusTable = initStatusTable({
    html, fatherElement: statusTableContainer, locale,
  })

  await statusTable.refresh()
  const ctx = document.getElementById('myChart').getContext('2d')
  const myChart = new Chart(ctx, {
    type: 'doughnut',
    data,
    options: {
      responsive: true,
      plugins: {
        legend: {
          position: 'top',
        },
        title: {
          display: true,
          text: 'Top processes by memory',
        },
      },
    },
  })
  return myChart
}
