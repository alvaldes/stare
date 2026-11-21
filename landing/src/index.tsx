import { Hono } from 'hono'
import { Home } from './pages/home'
import { NotFound } from './pages/notfound'
import { renderer } from './renderer'

const app = new Hono()

app.use(renderer)

app.get('/', (c) => c.render(<Home />))

// Static assets answer every known path, so only unknown ones reach the Worker.
app.notFound((c) => {
  c.status(404)
  return c.render(<NotFound />, { title: 'Page not found · Stare', robots: 'noindex' })
})

export default app
