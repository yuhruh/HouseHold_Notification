import { Controller } from "@hotwired/stimulus"
import * as echarts from "echarts"

// M0 check X6: renders sample data with the custom ECharts build.
const MONTHS = ["1月", "2月", "3月", "4月", "5月", "6月"]

const OPTIONS = {
  bar: {
    tooltip: {},
    xAxis: { type: "category", data: MONTHS },
    yAxis: { type: "value" },
    series: [{ type: "bar", data: [4668, 5120, 3980, 6210, 4470, 5030] }]
  },
  boxplot: {
    tooltip: {},
    dataset: [
      { source: [[820, 950, 1100, 1240, 3900], [400, 610, 580, 720, 690], [1500, 1620, 1580, 1710, 1490]] },
      { transform: { type: "boxplot", config: { itemNameFormatter: ({ value }) => ["電費", "水費", "網路"][value] } } },
      { fromDatasetIndex: 1, fromTransformResult: 1 }
    ],
    xAxis: { type: "category" },
    yAxis: { type: "value" },
    series: [
      { type: "boxplot", datasetIndex: 1 },
      { type: "scatter", datasetIndex: 2 }
    ]
  }
}

export default class extends Controller {
  static values = { kind: String }

  connect() {
    this.chart = echarts.init(this.element)
    this.chart.setOption(OPTIONS[this.kindValue])
  }

  disconnect() {
    this.chart.dispose()
  }
}
