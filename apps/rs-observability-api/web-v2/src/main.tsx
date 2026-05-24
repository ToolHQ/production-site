import { render } from 'preact'
import './index.css'
import './app.css'
import './generated/cluster-badges.css'
import { App } from './app.tsx'

render(<App />, document.getElementById('app')!)

