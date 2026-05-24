import { dom } from './dom.js'

export class LinearProgress {
  constructor() {
    this.init()
  }

  init() {
    this.domElement = dom({
      tag: 'div',
      classes: ['mdc-linear-progress', 'mdc-linear-progress--indeterminate'],
      attributes: {
        role: 'progressbar',
      },
      children: [
        dom({ tag: 'div', classes: ['mdc-linear-progress__buffer'] }),
        dom({
          tag: 'div',
          classes: ['mdc-linear-progress__bar', 'mdc-linear-progress__primary-bar'],
          children: [
            dom({
              tag: 'span',
              classes: ['mdc-linear-progress__bar-inner'],
            }),
          ],
        }),
        dom({
          tag: 'div',
          classes: ['mdc-linear-progress__bar', 'mdc-linear-progress__secondary-bar'],
          children: [
            dom({
              tag: 'span',
              classes: ['mdc-linear-progress__bar-inner'],
            }),
          ],
        }),
      ],
    })
  }
}
