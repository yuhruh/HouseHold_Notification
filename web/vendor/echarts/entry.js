// Custom ECharts build for the dashboard (PRD §8, M0 check X6). Only the chart types and
// components the app uses, so importmap serves one self-contained file.
// Rebuild with bin/build-echarts after changing this list.
import * as echarts from "echarts/core"
import { BarChart, BoxplotChart, LineChart, PieChart, ScatterChart } from "echarts/charts"
import {
  DatasetComponent,
  GridComponent,
  LegendComponent,
  TitleComponent,
  TooltipComponent,
  TransformComponent
} from "echarts/components"
import { CanvasRenderer } from "echarts/renderers"

echarts.use([
  BarChart, BoxplotChart, LineChart, PieChart, ScatterChart,
  DatasetComponent, GridComponent, LegendComponent, TitleComponent, TooltipComponent, TransformComponent,
  CanvasRenderer
])

export * from "echarts/core"
