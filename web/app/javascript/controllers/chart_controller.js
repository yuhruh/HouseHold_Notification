import { Controller } from "@hotwired/stimulus"
import * as echarts from "echarts"

// Renders one dashboard chart (PRD §8) and drills down on click: points carry `filters` (loaded
// into the drill-down Turbo Frame) or a `record_id` (box plot outliers open the record).
export default class extends Controller {
  static values = { option: Object, drillUrl: String, recordUrl: String, frame: String }

  connect() {
    // Dark mode (header theme menu) uses ECharts' dark theme on the page's own background
    const theme = document.documentElement.dataset.theme
    const dark = theme === "dark" || (theme === "system" && window.matchMedia("(prefers-color-scheme: dark)").matches)
    this.chart = echarts.init(this.element, dark ? "dark" : null, { renderer: "canvas" })
    this.chart.setOption(dark ? { backgroundColor: "transparent", ...this.optionValue } : this.optionValue)
    this.fitLabels()
    this.chart.on("click", (params) => this.drill(params))
    this.resize = () => { this.fitLabels(); this.chart.resize() }
    window.addEventListener("resize", this.resize)
  }

  // Rotated x-axis labels (billing cycles, categories) get smaller and steeper on screens under 500px
  fitLabels() {
    const label = this.optionValue.xAxis?.axisLabel
    if (!label?.rotate) return
    const narrow = window.innerWidth < 500
    this.chart.setOption({ xAxis: { axisLabel: narrow ? { fontSize: 9, rotate: 50 } : { fontSize: 12, rotate: label.rotate } } })
  }

  disconnect() {
    window.removeEventListener("resize", this.resize)
    this.chart?.dispose()
  }

  drill(params) {
    const data = params.data || {}
    if (data.record_id) {
      window.Turbo.visit(this.recordUrlValue.replace("RECORD_ID", data.record_id))
      return
    }
    if (!data.filters) return
    const frame = document.getElementById(this.frameValue)
    frame.src = `${this.drillUrlValue}?${new URLSearchParams(data.filters)}`
    frame.scrollIntoView({ behavior: "smooth", block: "nearest" })
  }
}
