/**
 * @param {Object} options
 * @param {String} options.tag
 * @param {String} [options.innerText]
 * @param {String[]} [options.classes]
 * @param {Object.<String, String>} [options.attributes]
 * @param {HTMLElement[]} [options.children]
 */
export const dom = ({
  tag,
  innerText,
  classes = [],
  attributes = {},
  children = [],
}) => {
  const htmlElement = (tag === 'svg' || tag === 'polygon') ? document.createElementNS('http://www.w3.org/2000/svg', tag) : document.createElement(tag)
  classes.forEach((c) => htmlElement.classList.add(c))
  Object.entries(attributes).forEach(([qualifiedName, value]) => htmlElement.setAttribute(qualifiedName, value))
  if (innerText) htmlElement.innerText = innerText
  htmlElement.append(...children)
  return htmlElement
}

/**
 * @param {HTMLElement} parent
 * @param {HTMLElement} child
 */
export const append = (parent, child) => {
  parent.appendChild(child)
  return parent
}
