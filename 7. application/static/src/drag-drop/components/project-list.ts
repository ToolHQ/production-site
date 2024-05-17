import { Component } from './base-component';
import { autobind } from '../decorators/autobind';
import { Project, ProjectStatus, ProjectStringStatus, convertProjectStatus } from '../models/project';
import { projectState } from '../state/project-state';
import { DragTarget } from '../models/drag-drop';
import { ProjectItem } from './project-item';

// ProjectList Class
export class ProjectList extends Component<HTMLDivElement, HTMLElement> implements DragTarget {
  private projectListId: string;
  assignedProjects: Project[];

  constructor(private type: ProjectStringStatus) {
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
        const projectStatus = convertProjectStatus(this.type);
        return prj.status === projectStatus;
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
    const projectStatus = convertProjectStatus(this.type);
    projectState.moveProject(prjId, projectStatus);
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

