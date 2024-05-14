document.addEventListener('DOMContentLoaded', () => {
  const loginForm = document.getElementById('loginForm') as HTMLFormElement;
  const signupForm = document.getElementById('signupForm') as HTMLFormElement;
  const changePasswordForm = document.getElementById('changePasswordForm') as HTMLFormElement;
  const homePage = document.getElementById('homePage') as HTMLElement;
  const signupPage = document.getElementById('signupPage') as HTMLElement;
  const changePasswordPage = document.getElementById('changePasswordPage') as HTMLElement;
  const modal = document.getElementById('modal')!;
  const modalMessage = document.getElementById('modalMessage') as HTMLElement;
  const closeModalBtn = document.getElementById('closeModal') as HTMLElement;
  const signupLink = document.getElementById('signupLink')!;
  const loginLink = document.getElementById('loginLink')!;
  const backToHomeBtn = document.getElementById('backToHome')!;
  const forgotPasswordLinks = document.querySelectorAll('.forgot-password-link');

  loginForm.addEventListener('submit', (event) => {
    event.preventDefault();
    // Placeholder for login form submission logic
    displayModal('Login successful!');
    loginForm.reset();
  });

  signupForm.addEventListener('submit', (event) => {
    event.preventDefault();
    const { value: username } = document.getElementById('username') as HTMLInputElement;
    const { value: email } = document.getElementById('email') as HTMLInputElement;
    const { value: password } = document.getElementById('password') as HTMLInputElement;
    const { value: confirmPassword } = document.getElementById('confirmPassword') as HTMLInputElement;
    const { value: birthday } = document.getElementById('birthday') as HTMLInputElement;
    if (validateSignupForm(username, email, password, confirmPassword, birthday)) {
      // Display confirmation modal
      displayModal('Signup successful!');
      signupForm.reset();
    }
  });

  changePasswordForm.addEventListener('submit', (event) => {
    event.preventDefault();
    const { value: currentPassword } = document.getElementById('currentPassword') as HTMLInputElement;
    const { value: newPassword } = document.getElementById('newPassword') as HTMLInputElement;
    const { value: confirmNewPassword } = document.getElementById('confirmNewPassword') as HTMLInputElement;
    if (validateChangePasswordForm(currentPassword, newPassword, confirmNewPassword)) {
      // Placeholder for change password form submission logic
      displayModal('Password changed successfully!');
      changePasswordForm.reset();
    }
  });

  closeModalBtn.addEventListener('click', () => {
    // Close modal
    modal.style.display = 'none';
  });

  signupLink.addEventListener('click', (event) => {
    event.preventDefault();
    showPage(signupPage);
  });

  loginLink.addEventListener('click', (event) => {
    event.preventDefault();
    showPage(homePage);
  });

  backToHomeBtn.addEventListener('click', () => {
    showPage(homePage);
  });

  forgotPasswordLinks.forEach((link) => {
    link.addEventListener('click', (event) => {
      event.preventDefault();
      showPage(changePasswordPage);
    });
  });

  const validateSignupForm = (username: string, email: string, password: string, confirmPassword: string, birthday: string) => {
    // Simple validation for empty fields
    if (username.trim() === '' || email.trim() === '' || password.trim() === '' || confirmPassword.trim() === '' || birthday.trim() === '') {
      displayModal('Please fill in all fields');
      return false;
    }
    // Validate password length and complexity
    if (password.length < 8) {
      displayModal('Password must be at least 8 characters long');
      return false;
    }
    if (!/[A-Z]/.test(password) || !/[a-z]/.test(password) || !/\d/.test(password)) {
      displayModal('Password must contain at least one uppercase letter, one lowercase letter, and one digit');
      return false;
    }
    // Confirm password
    if (password !== confirmPassword) {
      displayModal('Passwords do not match');
      return false;
    }
    return true;
  }

  const validateChangePasswordForm = (currentPassword: string, newPassword: string, confirmNewPassword: string) => {
    // Simple validation for empty fields
    if (currentPassword.trim() === '' || newPassword.trim() === '' || confirmNewPassword.trim() === '') {
      displayModal('Please fill in all fields');
      return false;
    }
    // Placeholder for more advanced password validation
    // Confirm new password
    if (newPassword !== confirmNewPassword) {
      displayModal('New passwords do not match');
      return false;
    }
    return true;
  }

  const displayModal = (message: string) => {
    // Display modal with message
    modalMessage.textContent = message;
    modal.style.display = 'block';
  }

  const showPage = (page: HTMLElement) => {
    homePage.style.display = 'none';
    signupPage.style.display = 'none';
    changePasswordPage.style.display = 'none';
    page.style.display = 'block';
  }
});
