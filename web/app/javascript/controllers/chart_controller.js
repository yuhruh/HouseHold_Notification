import { Controller } from "@hotwired/stimulus"
import * as echarts from "echarts"

// Renders one dashboard chart (PRD §8) and drills down on click: points carry `filters` (loaded
// into the drill-down Turbo Frame) or a `record_id` (box plot outliers open the record).
export default class extends Controller {
  static values = { option: Object, drillUrl: String, recordUrl: String, frame: String }

  connect() {
    this.chart = echarts.init(this.element, null, { renderer: "canvas" })
    this.chart.setOption(this.optionValue)
    this.chart.on("click", (params) => this.drill(params))
    this.resize = () => this.chart.resize()
    window.addEventListener("resize", this.resize)
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
