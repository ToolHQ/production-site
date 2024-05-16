import { Component } from './base-component.js';
import { autobind } from '../decorators/autobind.js';
import { Project, ProjectStatus } from '../models/project.js';
import { projectState } from '../state/project-state.js';
import { DragTarget } from '../models/drag-drop.js';
import { ProjectItem } from './project-item.js';

// ProjectList Class
export class ProjectList extends Component<HTMLDivElement, HTMLElement> implements DragTarget {
  private projectListId: string;
  assignedProjects: Project[];

  constructor(private type: 'active' | 'finished') {
    super('project-list', 'app', false, `${type}-projects`);
    this.projectListId = `${type}-projects-list`;
    this.assignedProjects = [];
    this.configure();
    this.renderContent();
  }

  configure() {
    this.element.addEventListener('dragover', this.dragOverHandler);
    this.element.addEventListener('dragleave', this.dragLeaveHandler);
    this.element.addEventListener('drop', this.dropHandler);
    projectState.addListener((projects) => {
      this.assignedProjects = projects.filter((prj) => {
        if (this.type === 'active') {
          return prj.status === ProjectStatus.Active; 
        }
        return prj.status === ProjectStatus.Finished;
      });
      this.renderProjects();
    })
  }

  @autobind
  dragOverHandler(event: DragEvent): void {
    if (event.dataTransfer?.types[0] === 'text/plain') {
      event.preventDefault();
      const listEl = this.element.querySelector('ul')!;
      listEl.classList.add('droppable');
    }
  }

  @autobind
  dropHandler(event: DragEvent): void {
    const prjId = event.dataTransfer!.getData('text/plain');
    projectState.moveProject(prjId, this.type === 'active' ? ProjectStatus.Active : ProjectStatus.Finished);
  }

  @autobind
  dragLeaveHandler(_: DragEvent): void {
    const listEl = this.element.querySelector('ul')!;
    listEl.classList.remove('droppable');
  }

  renderContent() {
    this.element.querySelector('ul')!.id = this.projectListId;
    this.element.querySelector('h2')!.textContent = `${this.type.toUpperCase()} PROJECTS`;
  }

  private renderProjects() {
    const listEl = document.getElementById(this.projectListId) as HTMLUListElement;
    listEl.innerHTML = '';
    for (const prjItem of this.assignedProjects) {
      new ProjectItem(this.projectListId, prjItem)
    }
  }
}

