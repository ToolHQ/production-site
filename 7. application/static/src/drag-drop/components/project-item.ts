
import { Draggable } from '../models/drag-drop';
import { Component } from './base-component';
import { autobind } from '../decorators/autobind';
import { Project } from '../models/project';

// ProjectItem Class
export class ProjectItem extends Component<HTMLUListElement, HTMLLIElement> implements Draggable {

  get persons() {
    return this.project.people === 1
      ? '1 person'
      : `${this.project.people} persons`;
  }

  constructor(hostId: string, private project: Project) {
    super('single-project', hostId, false, project.id);
    this.configure();
    this.renderContent();
  }

  @autobind
  dragStartHandler(event: DragEvent): void {
    if (event.dataTransfer) {
      event.dataTransfer.setData('text/plain', this.project.id);
      event.dataTransfer.effectAllowed = 'move';  
    }
  }

  @autobind
  dragEndHandler(_: DragEvent): void {
    console.log('DragEnd');
  }

  configure(): void {
    this.element.addEventListener('dragstart', this.dragStartHandler);
    this.element.addEventListener('dragend', this.dragEndHandler);
  }

  renderContent(): void {
    this.element.querySelector('h2')!.textContent = this.project.title;
    this.element.querySelector('h3')!.textContent = `${this.persons} assigned`;
    this.element.querySelector('p')!.textContent = this.project.description;
  }
}
