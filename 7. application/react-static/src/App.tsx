import React, { useState } from 'react';

import TodoList from './components/TodoList';
import NewTodo from './components/NewTodo';
import { Todo } from './todo.model';

let id = 0

const App: React.FC = () => {
  const [todos, setTodos] = useState<Todo[]>([]);

  const todoAddHandler = (text: string) => {
    setTodos((prevTodos) => {
      const newTodo = {
        id: `t${++id}`,
        text
      }
      const newTodos = [
        ...prevTodos.filter(Boolean),
        newTodo
      ]
      return newTodos;
    });
  };

  const todoDeleteHandler = (todoId: string) => {
    setTodos((prevTodos) => prevTodos.filter(todo => todo.id !== todoId));
  };

  return (
    <div className='App'>
      <NewTodo onAddTodo={todoAddHandler}/>
      <TodoList items={todos} onDeleteTodo={todoDeleteHandler}/>
    </div>
  );
}

export default App;
