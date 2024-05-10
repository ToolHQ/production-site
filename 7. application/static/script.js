document.addEventListener('DOMContentLoaded', function() {
  const loginForm = document.getElementById('loginForm');
  const signupForm = document.getElementById('signupForm');
  const changePasswordForm = document.getElementById('changePasswordForm');
  const homePage = document.getElementById('homePage');
  const signupPage = document.getElementById('signupPage');
  const changePasswordPage = document.getElementById('changePasswordPage');
  const modal = document.getElementById('modal');
  const modalMessage = document.getElementById('modalMessage');
  const closeModalBtn = document.getElementById('closeModal');
  const signupLink = document.getElementById('signupLink');
  const loginLink = document.getElementById('loginLink');
  const backToHomeBtn = document.getElementById('backToHome');
  const forgotPasswordLinks = document.querySelectorAll('.forgot-password-link');

  loginForm.addEventListener('submit', function(event) {
      event.preventDefault();
      // Placeholder for login form submission logic
      displayModal('Login successful!');
      loginForm.reset();
  });

  signupForm.addEventListener('submit', function(event) {
      event.preventDefault();
      const username = document.getElementById('username').value;
      const email = document.getElementById('email').value;
      const password = document.getElementById('password').value;
      const confirmPassword = document.getElementById('confirmPassword').value;
      const birthday = document.getElementById('birthday').value;
      if (validateSignupForm(username, email, password, confirmPassword, birthday)) {
          // Display confirmation modal
          displayModal('Signup successful!');
          signupForm.reset();
      }
  });

  changePasswordForm.addEventListener('submit', function(event) {
      event.preventDefault();
      const currentPassword = document.getElementById('currentPassword').value;
      const newPassword = document.getElementById('newPassword').value;
      const confirmNewPassword = document.getElementById('confirmNewPassword').value;
      if (validateChangePasswordForm(currentPassword, newPassword, confirmNewPassword)) {
          // Placeholder for change password form submission logic
          displayModal('Password changed successfully!');
          changePasswordForm.reset();
      }
  });

  closeModalBtn.addEventListener('click', function() {
      // Close modal
      modal.style.display = 'none';
  });

  signupLink.addEventListener('click', function(event) {
      event.preventDefault();
      showPage(signupPage);
  });

  loginLink.addEventListener('click', function(event) {
      event.preventDefault();
      showPage(homePage);
  });

  backToHomeBtn.addEventListener('click', function() {
      showPage(homePage);
  });

  forgotPasswordLinks.forEach(function(link) {
      link.addEventListener('click', function(event) {
          event.preventDefault();
          showPage(changePasswordPage);
      });
  });

  function validateSignupForm(username, email, password, confirmPassword, birthday) {
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

  function validateChangePasswordForm(currentPassword, newPassword, confirmNewPassword) {
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

  function displayModal(message) {
      // Display modal with message
      modalMessage.textContent = message;
      modal.style.display = 'block';
  }

  function showPage(page) {
      homePage.style.display = 'none';
      signupPage.style.display = 'none';
      changePasswordPage.style.display = 'none';
      page.style.display = 'block';
  }
});
