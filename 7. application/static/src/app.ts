import { ProjectList } from './drag-drop/components/project-list';
import { ProjectInput } from './drag-drop/components/project-input';
import { configureHome } from './home';
import { configureMapsPage } from './maps'

if (window.location.pathname === '/drag-drop.html') {
  new ProjectInput();
  new ProjectList('active');
  new ProjectList('in-progress');
  new ProjectList('finished');
} else if (window.location.pathname === '/maps.html') {
  configureMapsPage();
} else {
  document.addEventListener('DOMContentLoaded', configureHome);  
}